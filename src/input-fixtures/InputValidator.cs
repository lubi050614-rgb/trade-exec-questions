using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Globalization;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

namespace TradeInputs {
public static class InputValidation {
    static JavaScriptSerializer J(){return new JavaScriptSerializer{MaxJsonLength=Int32.MaxValue};}
    static Dictionary<string,object> D(object x){return (Dictionary<string,object>)x;}
    static long L(object x){return Convert.ToInt64(x,CultureInfo.InvariantCulture);}
    static decimal N(object x){return Convert.ToDecimal(x,CultureInfo.InvariantCulture);}
    static string S(object x){return Convert.ToString(x,CultureInfo.InvariantCulture);}
    static DateTimeOffset T(object x){return DateTimeOffset.Parse(S(x),CultureInfo.InvariantCulture);}
    static void Need(bool b,string reason){if(!b)throw new InvalidDataException(reason);}
    static IEnumerable<Dictionary<string,object>> Rows(string path) {
        using(var r=new StreamReader(path,Encoding.UTF8)){string line;var j=J();while((line=r.ReadLine())!=null){if(line.Length>0)yield return D(j.DeserializeObject(line));}}
    }
    static string H(string p){using(var s=File.OpenRead(p))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","").ToLowerInvariant();}
    static string Relative(string root,string path) {
        Need(!Path.IsPathRooted(path)&&path.StartsWith("synthetic/",StringComparison.Ordinal),"Input path must stay in synthetic namespace");
        string full=Path.GetFullPath(Path.Combine(root,path.Replace('/',Path.DirectorySeparatorChar)));
        Need(full.StartsWith(Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase),"Input path escapes root");return full;
    }
    static void Type(object x,string type) {
        if(type.StartsWith("Nullable(")){if(x==null)return;Type(x,type.Substring(9,type.Length-10));return;}
        Need(x!=null,"Null for nonnullable field "+type);
        if(type.StartsWith("LowCardinality(")){Type(x,type.Substring(15,type.Length-16));return;}
        if(type.StartsWith("Array(")){Need(x is object[],"Expected array");foreach(var v in (object[])x)Type(v,type.Substring(6,type.Length-7));return;}
        if(type=="String"){Need(x is string,"Expected string");return;}
        if(type=="UUID"){Guid g;Need(Guid.TryParse(S(x),out g),"Invalid UUID");return;}
        if(type.StartsWith("Date")){DateTimeOffset dt;Need(x is string&&DateTimeOffset.TryParse(S(x),CultureInfo.InvariantCulture,DateTimeStyles.None,out dt),"Invalid date");return;}
        if(type.StartsWith("UInt")||type.StartsWith("Int")){decimal n=N(x);Need(n==Decimal.Truncate(n),"Fractional integer");if(type.StartsWith("UInt"))Need(n>=0,"Negative unsigned integer");return;}
        if(type.StartsWith("Float")||type.StartsWith("Decimal")){double v=Convert.ToDouble(x,CultureInfo.InvariantCulture);Need(!Double.IsNaN(v)&&!Double.IsInfinity(v),"Invalid numeric value");return;}
        throw new InvalidDataException("Unsupported schema type "+type);
    }
    static string EventKey(Dictionary<string,object> e){return String.Join("|",new[]{"event_id","parent_order_id","child_order_id","event_type","qty","price_ticks","fee_minor","event_time"}.Select(k=>S(e[k])));}
    static void CheckFill(long accepted,long old,long added){Need(added>0&&old+added<=accepted,"Overfill or nonpositive fill");}
    static void CheckDuplicate(string old,string current){Need(old==current,"Conflicting duplicate physical event");}
    static void CheckRelease(DateTimeOffset release,DateTimeOffset confirm){Need(release>=confirm,"Frozen budget released before cancel confirmation");}
    static void CheckStock(long total,long sellable,long frozen,long today){Need(total>=0&&sellable>=0&&frozen>=0&&today>=0&&total==sellable+frozen+today,"Inventory invariant violated");}
    static void CheckTime(DateTimeOffset physical,DateTimeOffset visible){Need(physical<=visible,"Observation visible before physical event");}
    public static int SelfTest() {
        Action[] bad={()=>CheckFill(500,400,200),()=>CheckDuplicate("fill:100","fill:200"),()=>CheckRelease(DateTimeOffset.MinValue,DateTimeOffset.MinValue.AddSeconds(1)),()=>CheckStock(100,100,100,0),()=>CheckTime(DateTimeOffset.MinValue.AddSeconds(1),DateTimeOffset.MinValue),()=>Relative(Path.GetTempPath(),"synthetic/../../escape")};
        int count=0;foreach(var test in bad){bool rejected=false;try{test();}catch(InvalidDataException){rejected=true;}Need(rejected,"Negative test was accepted");count++;}return count;
    }
    public static string Validate(string root,string schemaJson,bool selfTest) {
        var json=J();var manifest=D(json.DeserializeObject(File.ReadAllText(Path.Combine(root,"manifest.json"),Encoding.UTF8)));
        Need(S(manifest["source_class"])=="synthetic_test_only"&&L(manifest["answers_generated"])==0,"Wrong source/answer claim");
        int symbols=(int)L(manifest["actual_n_symbols"]),days=(int)L(manifest["actual_n_days"]);Need(days==5&&symbols>0,"Invalid universe");
        var schema=D(json.DeserializeObject(schemaJson));long totalRows=0;int files=0;
        foreach(object item in (object[])manifest["files"]) {
            var meta=D(item);string path=S(meta["path"]);string full=Relative(root,path);
            Need(File.Exists(full)&&H(full)==S(meta["sha256"]),"Missing or changed file: "+path);
            string table=S(meta["table_schema"]);Dictionary<string,object> tableSchema=null;
            if(table.Length>0){Need(schema.ContainsKey(table),"Unknown table "+table);tableSchema=D(schema[table]);}
            long rows=0;foreach(var row in Rows(full)) {
                rows++;
                foreach(var field in row){Need(field.Key!="answer"&&field.Key!="expected_output"&&field.Key!="solution","Answer field in input");if(tableSchema!=null){Need(tableSchema.ContainsKey(field.Key),"Unknown real column "+table+"."+field.Key);Type(field.Value,S(tableSchema[field.Key]));}}
                if(row.ContainsKey("event_time")&&row.ContainsKey("available_at"))CheckTime(T(row["event_time"]),T(row["available_at"]));
            }
            Need(rows==L(meta["rows"]),"Row count mismatch: "+path);files++;totalRows+=rows;
        }
        string market=Path.Combine(root,"synthetic","market");
        var minuteTotals=new Dictionary<string,long[]>();long minuteRows=0;
        foreach(var r in Rows(Path.Combine(market,"rq_stock_bar_1m_local.jsonl"))) {
            string key=S(r["security_code"])+"|"+S(r["trade_date"]);long[] a;if(!minuteTotals.TryGetValue(key,out a)){a=new long[3];minuteTotals[key]=a;}
            Need(N(r["low"])<=N(r["open"])&&N(r["low"])<=N(r["close"])&&N(r["high"])>=N(r["open"])&&N(r["high"])>=N(r["close"]),"Invalid OHLC");
            Need(L(r["volume"])>=0&&N(r["total_turnover"])>=0,"Negative volume/amount");
            a[0]+=L(r["volume"]);a[1]+=L(N(r["total_turnover"])*100);a[2]++;minuteRows++;
        }
        Need(minuteTotals.Count==symbols*days&&minuteRows==symbols*days*240L,"Minute universe coverage mismatch");
        var previousClose=new Dictionary<string,decimal>();long dailyRows=0;
        foreach(var r in Rows(Path.Combine(market,"rq_stock_bar_1d_local.jsonl"))) {
            string sym=S(r["security_code"]),key=sym+"|"+S(r["trade_date"]);Need(minuteTotals.ContainsKey(key),"Daily/minute mismatch");long[] a=minuteTotals[key];
            Need(a[0]==L(r["volume"])&&a[1]==L(N(r["total_turnover"])*100)&&a[2]==240,"Daily/minute volume or amount mismatch");
            if(previousClose.ContainsKey(sym))Need(previousClose[sym]==N(r["prev_close"]),"Previous close chain broken");previousClose[sym]=N(r["close"]);dailyRows++;
        }
        Need(dailyRows==symbols*days,"Daily universe mismatch");
        foreach(var r in Rows(Path.Combine(market,"wind_quote_local.jsonl"))) {
            for(int k=1;k<=10;k++){Need(L(r["bid_price_"+k])<L(r["ask_price_"+k]),"Crossed snapshot");Need(L(r["bid_volume_"+k])>=0&&L(r["ask_volume_"+k])>=0,"Negative depth");if(k>1)Need(L(r["bid_price_"+(k-1)])>L(r["bid_price_"+k])&&L(r["ask_price_"+(k-1)])<L(r["ask_price_"+k]),"Book sorting error");}
        }
        var rawOrders=new HashSet<long>();foreach(var r in Rows(Path.Combine(market,"wind_order_local.jsonl")))Need(rawOrders.Add(L(r["order_no"])),"Duplicate raw order ID");
        foreach(var r in Rows(Path.Combine(market,"wind_trade_local.jsonl")))Need(rawOrders.Contains(L(r["bid_order_id"]))&&rawOrders.Contains(L(r["ask_order_id"])),"Unresolved synthetic order reference");
        string business=Path.Combine(root,"synthetic","business");var events=new Dictionary<string,Dictionary<string,object>>();long deliveries=0;
        foreach(var e in Rows(Path.Combine(business,"observations.jsonl"))) {
            string id=S(e["event_id"]);Dictionary<string,object> old;if(events.TryGetValue(id,out old))CheckDuplicate(EventKey(old),EventKey(e));else events[id]=e;deliveries++;
        }
        var accepted=new Dictionary<string,Dictionary<string,object>>();var filled=new Dictionary<string,long>();var cancels=new Dictionary<string,DateTimeOffset>();
        foreach(var e in events.Values.Where(e=>S(e["event_type"])=="ACCEPTED")){string child=S(e["child_order_id"]);Need(!accepted.ContainsKey(child),"Duplicate business acceptance");accepted[child]=e;filled[child]=0;}
        var initialCash=Rows(Path.Combine(business,"initial_balances.jsonl")).Single();
        Need(L(initialCash["cash_frozen_minor"])==0&&L(initialCash["cash_in_transit_minor"])==0,"Unsupported initial frozen/transit baseline");
        long openingCash=L(initialCash["cash_available_minor"]),independentCash=openingCash;
        var openingPositions=Rows(Path.Combine(business,"initial_positions.jsonl")).ToArray();
        Need(openingPositions.Length==symbols,"Initial position universe mismatch");
        var positions=new Dictionary<string,long>();foreach(var p in openingPositions)positions.Add(S(p["security_code"]),L(p["qty_total"]));
        foreach(var e in events.Values.OrderBy(e=>T(e["event_time"])).ThenBy(e=>L(e["source_seq"]))) {
            string type=S(e["event_type"]),child=S(e["child_order_id"]);
            if(type=="FILL") {
                Need(accepted.ContainsKey(child),"Fill without acceptance");Need(T(accepted[child]["event_time"])<=T(e["event_time"]),"Fill before acceptance");CheckFill(L(accepted[child]["qty"]),filled[child],L(e["qty"]));filled[child]+=L(e["qty"]);
                long sign=S(e["side"])=="buy"?1:-1;positions[S(e["security_code"])]+=sign*L(e["qty"]);independentCash-=sign*L(e["qty"])*L(e["price_ticks"])+L(e["fee_minor"]);
            }
            if(type=="CANCELLED"){Need(accepted.ContainsKey(child)&&filled[child]+L(e["qty"])==L(accepted[child]["qty"]),"Cancel quantity does not conserve");cancels[child]=T(e["event_time"]);}
        }
        var stock=new Dictionary<string,long[]>();foreach(var p in openingPositions){var a=new long[]{L(p["qty_total"]),L(p["qty_sellable"]),L(p["qty_frozen"]),L(p["qty_today_buy"])};CheckStock(a[0],a[1],a[2],a[3]);stock.Add(S(p["security_code"]),a);}long availableCash=openingCash,frozenCash=0;
        foreach(var f in Rows(Path.Combine(business,"ledger-flows.jsonl")).OrderBy(f=>T(f["event_time"])).ThenBy(f=>S(f["entry_id"]),StringComparer.Ordinal)) {
            string sym=S(f["security_code"]),kind=S(f["entry_type"]),child=S(f["child_order_id"]);
            if(kind=="CANCEL_RELEASE"){Need(cancels.ContainsKey(child),"Release without cancel confirmation");CheckRelease(T(f["event_time"]),cancels[child]);}
            availableCash+=L(f["delta_cash_available_minor"]);frozenCash+=L(f["delta_cash_frozen_minor"]);Need(availableCash>=0&&frozenCash>=0,"Negative cash budget");
            var a=stock[sym];a[0]+=L(f["delta_qty_total"]);a[1]+=L(f["delta_qty_sellable"]);a[2]+=L(f["delta_qty_frozen"]);a[3]+=L(f["delta_qty_today_buy"]);CheckStock(a[0],a[1],a[2],a[3]);
        }
        Need(frozenCash==0&&availableCash==independentCash,"Independent cash/ledger mismatch");foreach(var p in positions)Need(stock[p.Key][0]==p.Value&&stock[p.Key][2]==0,"Independent inventory/ledger mismatch");
        string canonical="cash:"+independentCash.ToString(CultureInfo.InvariantCulture)+"\n";foreach(var p in positions.OrderBy(p=>p.Key,StringComparer.Ordinal))canonical+=p.Key+":"+p.Value.ToString(CultureInfo.InvariantCulture)+"\n";
        string digest;using(var sha=SHA256.Create())digest=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-","").ToLowerInvariant();
        string internalFile=Path.Combine(root,"_internal","state-digest.jsonl");bool internalChecked=File.Exists(internalFile);if(internalChecked)Need(S(Rows(internalFile).Single()["sha256"])==digest,"Generator/internal reference mismatch");
        foreach(var r in Rows(Path.Combine(root,"synthetic","protocol","fix-messages.jsonl"))) {
            string wire=S(r["wire"]);int last=wire.LastIndexOf("10=",StringComparison.Ordinal);Need(last>0,"FIX checksum absent");int sum=Encoding.ASCII.GetBytes(wire.Substring(0,last)).Sum(b=>(int)b)%256;Need(sum==Int32.Parse(wire.Substring(last+3,3),CultureInfo.InvariantCulture),"FIX checksum mismatch");
            int bodyBegin=wire.IndexOf('\u0001',wire.IndexOf("9=",StringComparison.Ordinal))+1;int n=Int32.Parse(wire.Substring(wire.IndexOf("9=",StringComparison.Ordinal)+2,bodyBegin-wire.IndexOf("9=",StringComparison.Ordinal)-3),CultureInfo.InvariantCulture);Need(Encoding.ASCII.GetByteCount(wire.Substring(bodyBegin,last-bodyBegin))==n,"FIX body length mismatch");
        }
        var profileSum=new Dictionary<string,double>();
        foreach(var r in Rows(Path.Combine(root,"synthetic","models","volume-profile.jsonl"))){string sym=S(r["security_code"]);if(!profileSum.ContainsKey(sym))profileSum[sym]=0;Need(N(r["weight"])>=0,"Negative profile weight");profileSum[sym]+=Convert.ToDouble(r["weight"],CultureInfo.InvariantCulture);}
        Need(profileSum.Count==symbols&&profileSum.Values.All(v=>Math.Abs(v-1)<1e-10),"Profile normalization error");
        foreach(var r in Rows(Path.Combine(root,"synthetic","special","derivatives.jsonl"))){Need(N(r["multiplier"])>0&&N(r["price_tick"])>0,"Invalid derivative unit");Need(N(r["quote_price"])%N(r["price_tick"])==0,"Off-tick derivative price");Need(L(r["reported_fill_qty"])<=L(r["requested_qty"]),"Derivative overfill input");}
        var baskets=new Dictionary<string,HashSet<string>>();
        foreach(var r in Rows(Path.Combine(root,"synthetic","special","pcf.jsonl"))){string id=S(r["scenario_id"]);if(!baskets.ContainsKey(id))baskets[id]=new HashSet<string>();Need(baskets[id].Add(S(r["component_code"])),"Duplicate PCF component");Need(L(r["component_qty"])>0&&L(r["creation_unit"])>0,"Invalid PCF quantity");Need(r["cash_substitution"]!=null||S(r["variant"])=="missing_evidence","Unexpected missing PCF flag");}
        Need(baskets.Count==4&&baskets.Values.All(b=>b.Count==symbols),"Synthetic basket universe mismatch");
        int negatives=selfTest?SelfTest():0;
        return json.Serialize(new Dictionary<string,object>{{"result","passed"},{"actual_n_symbols",symbols},{"actual_n_days",days},{"public_files",files},{"rows_checked",totalRows},{"minute_rows",minuteRows},{"business_deliveries",deliveries},{"unique_physical_events",events.Count},{"duplicate_deliveries",deliveries-events.Count},{"internal_digest_checked",internalChecked},{"negative_cases_rejected",negatives},{"answers_generated",0},{"real_market_data",false},{"real_calibration_ready",false},{"book_fidelity","sampled_reset_blocks_not_complete_l3"}});
    }
}
}
