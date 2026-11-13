using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

namespace TradeInputs {
public sealed class Generator : IDisposable {
    readonly string root;
    readonly JavaScriptSerializer json = new JavaScriptSerializer { MaxJsonLength = Int32.MaxValue };
    readonly Dictionary<string,StreamWriter> writers = new Dictionary<string,StreamWriter>();
    readonly Dictionary<string,long> counts = new Dictionary<string,long>();
    readonly Dictionary<string,string[]> columns = new Dictionary<string,string[]>();
    uint rng;
    long[,,] minuteOpenTicks;
    public Generator(string directory, int seed) { root=directory; rng=(uint)seed; }
    public static Dictionary<string,object> R(params object[] fields) {
        var r=new Dictionary<string,object>();
        for(int i=0;i<fields.Length;i+=2) r.Add((string)fields[i], fields[i+1]);
        return r;
    }
    int Next(int max) { rng ^= rng<<13; rng ^= rng>>17; rng ^= rng<<5; return (int)(rng%(uint)max); }
    public static string Stamp(DateTime t) { return t.ToString("yyyy-MM-ddTHH:mm:ss.fff",CultureInfo.InvariantCulture)+"+08:00"; }
    static DateTime Day(string s) { return DateTime.ParseExact(s,"yyyy-MM-dd",CultureInfo.InvariantCulture); }
    static DateTime MinuteStart(DateTime day,int m) { return day.AddHours(m<120?9:13).AddMinutes(m<120?30+m:m-120); }
    static string Symbol(int s) { return "SYN"+(s+1).ToString("D6"); }
    public void W(string path, Dictionary<string,object> row) {
        StreamWriter w;
        if(!writers.TryGetValue(path,out w)) {
            string full=Path.Combine(root,path.Replace('/',Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(full));
            w=new StreamWriter(full,false,new UTF8Encoding(false)); w.NewLine="\n";
            writers.Add(path,w);counts.Add(path,0);columns.Add(path,row.Keys.ToArray());
        }
        if(path.StartsWith("synthetic/business/",StringComparison.Ordinal))columns[path]=columns[path].Union(row.Keys).ToArray();
        w.WriteLine(json.Serialize(row)); counts[path]++;
    }
    void M(string table,Dictionary<string,object> row) { W("synthetic/market/"+table+".jsonl",row); }
    public void Dispose() { foreach(var w in writers.Values) w.Dispose(); writers.Clear(); }
    public string Catalog() {
        foreach(var w in writers.Values) w.Flush();
        return json.Serialize(counts.OrderBy(k=>k.Key,StringComparer.Ordinal).Select(k=>R("path",k.Key,"rows",k.Value,"columns",columns[k.Key])).ToArray());
    }
    public void Market(int n,string[] dates,int quoteInterval) {
        minuteOpenTicks=new long[n,dates.Length,240];
        for(int s=0;s<n;s++) {
            string sym=Symbol(s);
            M("rq_instrument_versions_local",R("market","SYN","security_code",sym,"asset_type","synthetic_stock","instrument_name",sym,"listed_date","2020-01-01","delisted_date",null,"round_lot","100","board_type","SYN_TEST_BOARD","status","Active","industry_code","SYN_I"+(s%5),"exchange","SYN","market_tplus","test_only_T1","createtime",Stamp(Day(dates[0]).AddDays(-4))));
            M("rq_adjustment_local",R("market","SYN","security_code",sym,"effective_date",dates[0],"adjustment_type","synthetic_identity","value",1.0));
            M("rq_financial_pit_local",R("market","SYN","security_code",sym,"info_date",Day(dates[0]).AddDays(-10).ToString("yyyy-MM-dd"),"metric","synthetic_profit","value",100000.0+s*100,"statement_type","synthetic","quarter","2026q3"));
        }
        long[] lastClose=Enumerable.Range(0,n).Select(s=>2000L+s*17).ToArray();
        for(int d=0;d<dates.Length;d++) {
            DateTime day=Day(dates[d]);
            M("rq_trading_calendar_local",R("trade_date",dates[d]));
            M("rq_risk_covariance_local",R("trade_date",dates[d],"model","synthetic_2f","factor_i","SYN_F1","factor_j","SYN_F1","value",1.0,"units","synthetic_daily_variance"));
            M("rq_risk_covariance_local",R("trade_date",dates[d],"model","synthetic_2f","factor_i","SYN_F2","factor_j","SYN_F2","value",1.0,"units","synthetic_daily_variance"));
            foreach(string[] pair in new[]{new[]{"SYN_F1","SYN_F2"},new[]{"SYN_F2","SYN_F1"}})
                M("rq_risk_covariance_local",R("trade_date",dates[d],"model","synthetic_2f","factor_i",pair[0],"factor_j",pair[1],"value",0.2,"units","synthetic_daily_variance"));
            for(int s=0;s<n;s++) {
                string sym=Symbol(s); long prev=lastClose[s]; long px=prev;
                long dailyOpen=0,dailyHigh=0,dailyLow=Int64.MaxValue,dailyVol=0,dailyMinor=0;
                bool suspended=(s==n-1&&d==dates.Length-1);
                M("rq_trading_status_local",R("market","SYN","security_code",sym,"trade_date",dates[d],"suspended",suspended?1:0,"st_flag",s%37==0?1:0,"limit_up",Math.Round(prev/100.0*1.1,2),"limit_down",Math.Round(prev/100.0*0.9,2)));
                M("rq_index_weight_local",R("index_market","SYN","index_code","SYN_INDEX","market","SYN","security_code",sym,"trade_date",dates[d],"weight",1.0/n));
                M("rq_factor_value_local",R("market","SYN","security_code",sym,"trade_date",dates[d],"factor_name","synthetic_liquidity_bucket","value",(double)(s%5),"factor_set","test_only","model","synthetic"));
                long bucketVolume=0,bucketMinor=0;int bucketQuotes=0;
                long lastQuoteTicks=prev;DateTime lastQuoteTime=day.AddHours(9).AddMinutes(30);
                for(int m=0;m<240;m++) {
                    DateTime t=MinuteStart(day,m); long open=px; px=suspended?prev:Math.Max(100,px+Next(5)-2);
                    minuteOpenTicks[s,d,m]=open;
                    long high=suspended?prev:Math.Max(open,px)+Next(3),low=suspended?prev:Math.Min(open,px)-Next(3);
                    long volume=suspended?0:100L*(1+s%5)*(5+Next(16)+(m<20||m>=220?20:0));
                    long amount=volume*(open+px)/2;
                    if(m==0)dailyOpen=open;dailyHigh=Math.Max(dailyHigh,high);dailyLow=Math.Min(dailyLow,low);dailyVol+=volume;dailyMinor+=amount;
                    bucketVolume+=volume;bucketMinor+=amount;
                    M("rq_stock_bar_1m_local",R("market","SYN","security_code",sym,"trade_date",dates[d],"bar_end",Stamp(t.AddMinutes(1)),"open",open/100.0,"high",high/100.0,"low",low/100.0,"close",px/100.0,"volume",volume,"total_turnover",amount/100.0,"num_trades",volume==0?0:Math.Max(1,volume/100),"iopv",null));
                    if(m%quoteInterval==0) {
                        lastQuoteTicks=open;lastQuoteTime=t;
                        bucketQuotes++;
                        long seq=(long)m*10+1,oid=1L+d*100000000L+s*100000L+m*10;
                        long[] bids=Enumerable.Range(1,10).Select(k=>open-k).ToArray();
                        long[] asks=Enumerable.Range(1,10).Select(k=>open+k).ToArray();
                        long[] depths=Enumerable.Range(1,10).Select(k=>1000L*(s%5+1)*k).ToArray();
                        var quote=R("market","SYN","security_code",sym,"trade_date",dates[d],"ts",Stamp(t),"price",open,"volume",0,"amount",0,"acc_volume",dailyVol-volume,"acc_amount",dailyMinor-amount,"trade_flag","SYN_SAMPLE","bs_flag","SYN_UNKNOWN","channel_id",s%4,"exchange_seq",seq);
                        for(int k=0;k<10;k++){quote["bid_price_"+(k+1)]=bids[k];quote["ask_price_"+(k+1)]=asks[k];quote["bid_volume_"+(k+1)]=depths[k];quote["ask_volume_"+(k+1)]=depths[k];}
                        M("wind_quote_local",quote);
                        M("wind_book_checkpoint_local",R("market","SYN","security_code",sym,"ts",Stamp(t),"trade_date",dates[d],"reconstruction_policy","synthetic_sample_reset","checkpoint_kind","sample_block_start","bid_prices",bids,"bid_volumes",depths,"ask_prices",asks,"ask_volumes",depths));
                        if(!suspended) {
                            M("wind_order_local",R("market","SYN","security_code",sym,"ts",Stamp(t.AddMilliseconds(1)),"trade_date",dates[d],"order_no",oid,"exchange_order_id",oid,"order_type","SYN_LIMIT_BUY","order_code","SYN_NEW","price",asks[0],"volume",100,"channel_id",s%4,"exchange_seq",seq+1));
                            M("wind_order_local",R("market","SYN","security_code",sym,"ts",Stamp(t.AddMilliseconds(2)),"trade_date",dates[d],"order_no",oid+1,"exchange_order_id",oid+1,"order_type","SYN_LIMIT_SELL","order_code","SYN_NEW","price",asks[0],"volume",100,"channel_id",s%4,"exchange_seq",seq+2));
                            M("wind_trade_local",R("market","SYN","security_code",sym,"ts",Stamp(t.AddMilliseconds(3)),"trade_date",dates[d],"trade_id",oid,"trade_code","SYN_TRADE","order_code","SYN_MATCH","bs_flag","SYN_BUY","price",asks[0],"volume",100,"ask_order_id",oid+1,"bid_order_id",oid,"channel_id",s%4,"exchange_seq",seq+3));
                        }
                        M("wind_book_quality_local",R("market","SYN","security_code",sym,"trade_date",dates[d],"window_start",Stamp(t),"window_end",Stamp(t.AddMinutes(quoteInterval)),"order_rows",suspended?0:2,"trade_rows",suspended?0:1,"quote_rows",1,"ambiguous_groups",0,"unresolved_refs",0,"gap_count",1,"reconstruction_policy","synthetic_sample_reset","confidence","partial_between_samples"));
                    }
                    if((m+1)%30==0) {
                        var f=R("symbol",sym,"trade_date",dates[d],"window_start",Stamp(MinuteStart(day,m-29)),"window_end",Stamp(t.AddMinutes(1)),"quote_coverage_ratio",bucketQuotes/30.0,"quote_age_ms",(t.AddMinutes(1)-lastQuoteTime).TotalMilliseconds,"semantics_confirmed",1,"price_divisor_known",1,"volume_multiplier_known",1,"quality_status","synthetic_sampled_not_full_feed","mid_price_last",lastQuoteTicks/100.0,"spread_last",0.02,"trade_volume",bucketVolume,"trade_amount",bucketMinor/100.0,"vwap",bucketVolume==0?(object)null:bucketMinor/(100.0*bucketVolume),"trade_semantics_ready",1,"order_semantics_ready",1,"feed_completeness_checked",1,"source_slice_complete",0,"formula_version","synthetic-v1");
                        M("qinml_l2_features_30m_v1",f);bucketVolume=0;bucketMinor=0;bucketQuotes=0;
                    }
                }
                M("rq_stock_bar_1d_local",R("market","SYN","security_code",sym,"trade_date",dates[d],"open",dailyOpen/100.0,"high",dailyHigh/100.0,"low",dailyLow/100.0,"close",px/100.0,"volume",dailyVol,"total_turnover",dailyMinor/100.0,"prev_close",prev/100.0,"limit_up",Math.Round(prev/100.0*1.1,2),"limit_down",Math.Round(prev/100.0*0.9,2),"iopv",null));
                lastClose[s]=px;
            }
        }
        M("qinml_l2_features_30m_batches_v1",R("batch_id","20261113-0000-4000-8000-000000000001","event_time",Stamp(Day(dates[dates.Length-1]).AddHours(16)),"status","synthetic_sampled","checks_passed",1,"row_count",n*dates.Length*8,"date_start",dates[0],"date_end",dates[dates.Length-1],"symbols",Enumerable.Range(0,n).Select(Symbol).ToArray(),"formula_version","synthetic-v1","config_hashes",new[]{"input-generation-v1"}));
    }
    readonly long[] stock = new long[10000];
    readonly long[] sellable = new long[10000];
    readonly long[] todayBought = new long[10000];
    long cash=100000000000L;
    int deliveryCounter;
    long physicalCounter;
    void Flow(string scenario,string child,string sym,string kind,DateTime t,long available,long frozen,long total,long sellableDelta,long frozenQty,long todayDelta) {
        W("synthetic/business/ledger-flows.jsonl",R("entry_id",scenario+"-"+kind,"scenario_id",scenario,"child_order_id",child,"account_id","SIM_ACCOUNT","security_code",sym,"entry_type",kind,"event_time",Stamp(t),"available_at",Stamp(t.AddMilliseconds(2)),"delta_cash_available_minor",available,"delta_cash_frozen_minor",frozen,"delta_qty_total",total,"delta_qty_sellable",sellableDelta,"delta_qty_frozen",frozenQty,"delta_qty_today_buy",todayDelta,"currency","CNY"));
    }
    void Visible(Dictionary<string,object> e,DateTime at,string scenario) {
        var copy=new Dictionary<string,object>(e);copy["delivery_id"]="DEL"+(++deliveryCounter).ToString("D8");copy["available_at"]=Stamp(at);copy["scenario_id"]=scenario;
        W("synthetic/business/observations.jsonl",copy);
    }
    Dictionary<string,object> E(string id,string parent,string child,string sym,string side,string type,long qty,long price,DateTime t,long fee) {
        return R("event_id",id,"parent_order_id",parent,"child_order_id",child,"cl_ord_id",child,"broker_order_id",child+"-B","source_seq",++physicalCounter,"status",type,"account_id","SIM_ACCOUNT","security_code",sym,"side",side,"event_type",type,"qty",qty,"price_ticks",price,"fee_minor",fee,"execution_id",type=="FILL"?id:null,"event_time",Stamp(t));
    }
    public void Business(int n,string[] dates) {
        W("synthetic/business/initial_balances.jsonl",R("account_id","SIM_ACCOUNT","snapshot_at",Stamp(Day(dates[0]).AddHours(8)),"available_at",Stamp(Day(dates[0]).AddHours(8)),"currency","CNY","cash_available_minor",cash,"cash_frozen_minor",0,"cash_in_transit_minor",0));
        for(int s=0;s<n;s++){stock[s]=10000;sellable[s]=10000;W("synthetic/business/initial_positions.jsonl",R("account_id","SIM_ACCOUNT","security_code",Symbol(s),"qty_total",10000,"qty_sellable",10000,"qty_today_buy",0,"qty_frozen",0,"available_at",Stamp(Day(dates[0]).AddHours(8))));}
        string[] names={"normal","duplicate_delivery","out_of_order","partial_then_cancel","unknown_acceptance","disconnect_recovery","insufficient_funds","shared_rate_limit","stale_quote","fenced_sender"};
        for(int d=0;d<dates.Length;d++) {
            for(int s=0;s<n;s++) {
                if(d>0&&todayBought[s]>0)Flow("DAY-"+d+"-"+s,"",Symbol(s),"DAY_ROLL",Day(dates[d]).AddHours(8),0,0,0,todayBought[s],0,-todayBought[s]);
                sellable[s]=stock[s];todayBought[s]=0;
            }
            for(int s=0;s<n;s++) {
                int scenario=(s+d)%names.Length;
                bool suspended=s==n-1&&d==dates.Length-1;
                string sid="CASE-"+d.ToString("D2")+"-"+s.ToString("D3"),sym=Symbol(s),parent="PAR-"+d+"-"+s,child=parent+"-C1";
                string side=s%2==0?"buy":"sell";long qty=scenario==7?600:500,mid=minuteOpenTicks[s,d,5+s/60],price=mid+(side=="buy"?1:-1);
                DateTime t=Day(dates[d]).AddHours(9).AddMinutes(35).AddSeconds(s);
                DateTime quoteTime=scenario==8?t.AddSeconds(-10):t.AddMilliseconds(-5);
                W("synthetic/business/decision_quotes.jsonl",R("security_code",sym,"market","SYN","event_time",Stamp(quoteTime),"available_at",Stamp(quoteTime),"bid_price_ticks",mid-1,"ask_price_ticks",mid+1,"bid_qty",1000,"ask_qty",1000,"price_divisor",100,"source","synthetic_control_quote_not_vendor_observation"));
                bool unchanged=s%31==0;
                W("synthetic/business/target_holdings.jsonl",R("target_case_id","TARGET-"+d+"-"+s,"account_id","SIM_ACCOUNT","strategy_id","SIM_STRATEGY","target_version","target-"+d,"security_code",sym,"market","SYN","current_qty",stock[s],"desired_qty",unchanged?stock[s]:stock[s]+(side=="buy"?qty:-qty),"available_at",Stamp(t),"decision_at",Stamp(t),"linked_parent_order_id",unchanged?null:parent));
                if(unchanged){W("synthetic/business/scenarios.jsonl",R("scenario_id",sid,"kind","no_change","parent_order_id",null,"security_code",sym,"trade_date",dates[d],"test_only",true,"fault_layer","none"));continue;}
                W("synthetic/business/scenarios.jsonl",R("scenario_id",sid,"kind",suspended?"suspended":names[scenario],"parent_order_id",parent,"security_code",sym,"trade_date",dates[d],"test_only",true,"fault_layer",scenario==1||scenario==2||scenario==5?"delivery":"request_or_control"));
                W("synthetic/business/parents.jsonl",R("account_id","SIM_ACCOUNT","strategy_id","SIM_STRATEGY","target_version","target-"+d,"parent_order_id",parent,"child_order_id",null,"security_code",sym,"market","SYN","side",side,"target_qty",qty,"decision_at",Stamp(t),"available_at",Stamp(t),"deadline",Stamp(Day(dates[d]).AddHours(14).AddMinutes(55)),"algo_version","test-only-v1"));
                W("synthetic/business/client_requests.jsonl",R("request_id",sid+"-REQ1","parent_order_id",parent,"child_order_id",child,"account_id","SIM_ACCOUNT","security_code",sym,"side",side,"qty",scenario==7?500:qty,"price_ticks",price,"event_time",Stamp(t),"available_at",Stamp(t),"quota_scope",sid,"max_requests_per_second",scenario==7?1:1000,"quote_available_at",Stamp(scenario==8?t.AddSeconds(-10):t.AddMilliseconds(-5)),"max_quote_age_ms",1000,"fencing_epoch",scenario==9?1:2,"active_fencing_epoch",2,"available_budget_minor",scenario==6?0:10000000));
                if(scenario==6||scenario==8||suspended) {
                    string reason=suspended?"SYN_SUSPENDED":scenario==6?"SYN_FUNDS":"SYN_STALE";
                    var reject=E(sid+"-REJ",parent,child,sym,side,"REJECTED",qty,price,t.AddMilliseconds(10),0);reject["reason"]=reason;
                    Visible(reject,t.AddMilliseconds(11),sid);continue;
                }
                if(scenario==9) {
                    W("synthetic/business/client_requests.jsonl",R("request_id",sid+"-REQ2","parent_order_id",parent,"child_order_id",child,"account_id","SIM_ACCOUNT","security_code",sym,"side",side,"qty",qty,"price_ticks",price,"event_time",Stamp(t.AddMilliseconds(1)),"available_at",Stamp(t.AddMilliseconds(1)),"quota_scope",sid,"max_requests_per_second",1000,"quote_available_at",Stamp(t),"max_quote_age_ms",1000,"fencing_epoch",2,"active_fencing_epoch",2,"available_budget_minor",10000000));
                    var fenced=E(sid+"-FENCED",parent,child,sym,side,"CONTROL_REJECT",qty,price,t.AddMilliseconds(1),0);fenced["reason"]="SYN_FENCED_EPOCH";Visible(fenced,t.AddMilliseconds(2),sid);
                }
                long acceptedQty=scenario==7?500:qty;
                long reserve=side=="buy"?acceptedQty*price+100:100;
                Flow(sid,child,sym,"RESERVE",t,-reserve,reserve,0,side=="sell"?-acceptedQty:0,side=="sell"?acceptedQty:0,0);
                var ack=E(sid+"-ACK",parent,child,sym,side,"ACCEPTED",acceptedQty,price,t.AddMilliseconds(10),0);
                Visible(ack,t.AddMilliseconds(scenario==2?500:scenario==4?1500:11),sid);
                if(scenario==4) {
                    Visible(E(sid+"-TIMEOUT",parent,child,sym,side,"REQUEST_TIMEOUT",acceptedQty,price,t.AddMilliseconds(100),0),t.AddMilliseconds(100),sid);
                    W("synthetic/business/broker_queries.jsonl",R("query_id",sid+"-QUERY","parent_order_id",parent,"child_order_id",child,"security_code",sym,"event_time",Stamp(t.AddMilliseconds(1200)),"available_at",Stamp(t.AddMilliseconds(1201)),"status","PARTIAL","order_qty",acceptedQty,"cum_filled_qty",200,"active_qty",acceptedQty-200));
                }
                if(scenario==7) {
                    W("synthetic/business/client_requests.jsonl",R("request_id",sid+"-REQ2","parent_order_id",parent,"child_order_id",parent+"-C2","account_id","SIM_ACCOUNT","security_code",sym,"side",side,"qty",100,"price_ticks",price,"event_time",Stamp(t.AddMilliseconds(20)),"available_at",Stamp(t.AddMilliseconds(20)),"quota_scope",sid,"max_requests_per_second",1,"quote_available_at",Stamp(t),"max_quote_age_ms",1000,"fencing_epoch",2,"active_fencing_epoch",2,"available_budget_minor",10000000));
                    var rate=E(sid+"-RATE",parent,parent+"-C2",sym,side,"REJECTED",100,price,t.AddMilliseconds(21),0);rate["reason"]="SYN_RATE";Visible(rate,t.AddMilliseconds(22),sid);
                }
                int chunks=scenario==3||scenario==4?1:scenario==5?2:1;
                long remaining=acceptedQty;
                long feesPaid=0;
                for(int k=0;k<chunks;k++) {
                    long filled=scenario==3||scenario==4||scenario==5&&k==0?200:remaining;
                    long fee=chunks==2?50:100;DateTime ft=t.AddMilliseconds(200+k*100);
                    var fill=E(sid+"-FILL"+k,parent,child,sym,side,"FILL",filled,price,ft,fee);
                    DateTime at=ft.AddMilliseconds(1);if(scenario==5&&k==1)at=t.AddSeconds(2);
                    Visible(fill,at,sid);if(scenario==1)Visible(fill,at.AddMilliseconds(1),sid);
                    if(side=="buy"){stock[s]+=filled;todayBought[s]+=filled;cash-=filled*price+fee;Flow(sid,child,sym,"FILL"+k,ft,0,-filled*price-fee,filled,0,0,filled);}else{if(sellable[s]<filled)throw new InvalidOperationException("Oversell");stock[s]-=filled;sellable[s]-=filled;cash+=filled*price-fee;Flow(sid,child,sym,"FILL"+k,ft,filled*price,-fee,-filled,0,-filled,0);}
                    feesPaid+=fee;
                    if(cash<0)throw new InvalidOperationException("Negative cash");remaining-=filled;
                    W("synthetic/business/settlement_flows.jsonl",R("settlement_id",sid+"-SET"+k,"execution_id",sid+"-FILL"+k,"account_id","SIM_ACCOUNT","security_code",sym,"side",side,"qty",filled,"gross_minor",filled*price,"fee_minor",fee,"event_time",Stamp(ft),"available_at",Stamp(Day(dates[d]).AddHours(16)),"fee_rule_version","test-fixed-100-per-order"));
                }
                if(remaining>0) {
                    DateTime ct=t.AddMilliseconds(scenario==4?2000:400);
                    Visible(E(sid+"-CANCEL_REQ",parent,child,sym,side,"CANCEL_REQUEST",remaining,price,ct,0),ct,sid);
                    Visible(E(sid+"-CANCEL_ACK",parent,child,sym,side,"CANCELLED",remaining,price,ct.AddMilliseconds(100),0),ct.AddMilliseconds(101),sid);
                    long release=(side=="buy"?remaining*price:0)+(100-feesPaid);
                    Flow(sid,child,sym,"CANCEL_RELEASE",ct.AddMilliseconds(100),release,-release,0,side=="sell"?remaining:0,side=="sell"?-remaining:0,0);
                }
                if(scenario==5)W("synthetic/business/broker_queries.jsonl",R("query_id",sid+"-RECONNECT","parent_order_id",parent,"child_order_id",child,"security_code",sym,"event_time",Stamp(t.AddSeconds(2)),"available_at",Stamp(t.AddSeconds(2)),"status","FILLED","order_qty",acceptedQty,"cum_filled_qty",acceptedQty,"active_qty",0));
            }
        }
        string canonical="cash:"+cash.ToString(CultureInfo.InvariantCulture)+"\n";
        for(int s=0;s<n;s++)canonical+=Symbol(s)+":"+stock[s].ToString(CultureInfo.InvariantCulture)+"\n";
        string digest;using(var sha=SHA256.Create())digest=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(canonical))).Replace("-","").ToLowerInvariant();
        W("_internal/state-digest.jsonl",R("kind","validator_only_not_question_input","sha256",digest));
    }
    static string Fix(params string[] fields) {
        string body=String.Join("\u0001",fields)+"\u0001";
        string head="8=FIX.4.4\u00019="+Encoding.ASCII.GetByteCount(body)+"\u0001"+body;
        int sum=Encoding.ASCII.GetBytes(head).Sum(b=>(int)b)%256;
        return head+"10="+sum.ToString("D3")+"\u0001";
    }
    public void Auxiliary(int n,string[] dates) {
        DateTime day=Day(dates[0]);
        W("synthetic/rules/rule-pack.jsonl",R("rule_id","SYN_STOCK_TEST","version","test-rules-1","review_status","test_only","market","SYN","board","SYN_TEST_BOARD","session","continuous","subject_scope","synthetic_only","effective_from",Stamp(day.AddDays(-10)),"effective_to",Stamp(day.AddMonths(1)),"published_at",Stamp(day.AddDays(-11)),"source_url","synthetic://test-rules-1","source_hash","not_official","deferred",false,"lot_size",100,"price_tick_minor",1,"max_participation",0.1,"sell_today_buys",false,"unknown_rule_action","rule_pending","price_band_reference","test_same_side_best","upper_multiplier",1.02,"lower_multiplier",0.98,"minimum_ticks_band",10,"fee_per_order_minor",100,"max_quote_age_ms",1000,"max_order_qty",10000));
        string[] phases={"preopen_cancel_allowed","preopen_cancel_forbidden","continuous_am","lunch","continuous_pm","closing_auction","closed"};
        string[] starts={"09:15","09:20","09:30","11:30","13:00","14:57","15:00"};
        string[] ends={"09:20","09:25","11:30","13:00","14:57","15:00","23:59"};
        for(int i=0;i<phases.Length;i++)W("synthetic/rules/sessions.jsonl",R("phase",phases[i],"start",starts[i],"end",ends[i],"cancel_allowed",i==0||i==2||i==4,"review_status","test_only"));
        foreach(string venue in new[]{"SYN_QMT","SYN_PTR","SYN_PB","SYN_CTP","SYN_IB","SYN_CRYPTO","SYN_FIX"})
            W("synthetic/protocol/capabilities.jsonl",R("venue",venue,"api_version","synthetic-dialect-1","adapter_version","test-1","capability","submit_cancel_query","unknown_acceptance","query_before_retry","quota_scope","scenario_shared","quota_weight",1,"review_status","test_only"));
        foreach(string[] err in new[]{new[]{"SYN_FUNDS","permanent"},new[]{"SYN_RATE","retry_after_budget"},new[]{"SYN_UNKNOWN","manual_review"},new[]{"SYN_STALE","refresh_then_recheck"}})
            W("synthetic/protocol/error-codes.jsonl",R("error_code",err[0],"retry_class",err[1],"max_attempts",2,"test_only",true));
        string[] fix={Fix("35=A","34=1","49=SYN_CLIENT","56=SYN_BROKER","98=0","108=30"),Fix("35=D","34=2","49=SYN_CLIENT","56=SYN_BROKER","11=SYN-ORDER-1","55=SYN000001","54=1","38=500","40=2","44=20.00"),Fix("35=8","34=3","49=SYN_BROKER","56=SYN_CLIENT","11=SYN-ORDER-1","17=SYN-EXEC-1","150=1","39=1","32=200","31=20.00","14=200","151=300"),Fix("35=8","34=3","43=Y","49=SYN_BROKER","56=SYN_CLIENT","11=SYN-ORDER-1","17=SYN-EXEC-1","150=1","39=1","32=200","31=20.00","14=200","151=300"),Fix("35=2","34=4","7=2","16=3"),Fix("35=4","34=2","123=Y","36=4")};
        for(int i=0;i<fix.Length;i++)W("synthetic/protocol/fix-messages.jsonl",R("packet_id","FIX-"+i,"wire",fix[i],"display",fix[i].Replace('\u0001','|'),"event_time",Stamp(day.AddHours(9).AddSeconds(i)),"available_at",Stamp(day.AddHours(9).AddSeconds(i).AddMilliseconds(2)),"dialect","synthetic_subset_not_broker_certification"));
        for(int i=0;i<1000;i++) {
            long start=1000000000L+i*100000;long delay=1000+i%17*100+(i%100==0?50000:0);
            W("synthetic/system/telemetry.jsonl",R("packet_id","PKT-"+i,"host_id","SYN_HOST","clock_domain","simulated_monotonic","receive_ns",start,"decode_ns",start+200,"decision_ns",start+600,"send_ns",start+delay,"ack_ns",start+delay+5000,"ptp_offset_ns",i%7-3,"nic_drop_count",i==500?1:0,"is_hardware_measurement",false));
            if(i<20) {
                string payload=i+"|Q|SYN000001|2000|100";
                W("synthetic/protocol/datagrams.jsonl",R("packet_id","UDP-"+i,"sequence",i,"encoding","synthetic_text_v1_not_STEP_FAST","payload_hex",BitConverter.ToString(Encoding.ASCII.GetBytes(payload)).Replace("-",""),"event_time",Stamp(day.AddHours(9).AddMilliseconds(i)),"available_at",Stamp(day.AddHours(9).AddMilliseconds(i+2))));
                W("synthetic/system/fpga-vectors.jsonl",R("cycle",i,"valid",i!=10,"price_ticks",2000+i,"qty",100,"dma_ready",i!=15,"reset",i==0,"price_width",32,"qty_width",32,"bitstream_version","synthetic-no-board"));
            }
        }
        W("synthetic/system/build-profile.jsonl",R("compiler","synthetic_config_only","target_cpu","x86-64-baseline","march_native",false,"lto",true,"pgo_training_burst_included",false,"numa_node",0,"rx_core",2,"strategy_core",3,"queue_kind","SPSC","capacity",1024,"hardware_evidence_available",false));
        foreach(string date in dates) {
            DateTime dt=Day(date);
            for(int s=0;s<n;s++) {
                W("synthetic/events/auction.jsonl",R("security_code",Symbol(s),"event_type","indicative_auction","event_time",Stamp(dt.AddHours(9).AddMinutes(19)),"available_at",Stamp(dt.AddHours(9).AddMinutes(19).AddMilliseconds(2)),"version","auction-test-1","indicative_price_ticks",2000+s*17,"matched_qty",1000+s*10,"unmatched_qty",(s%2==0?1:-1)*500,"review_status","test_only"));
                if(s%25==0)W("synthetic/events/announcements.jsonl",R("security_code",Symbol(s),"event_type","synthetic_index_review","event_time",Stamp(dt.AddDays(-1).AddHours(18)),"available_at",Stamp(dt.AddDays(-1).AddHours(18).AddMinutes(1)),"effective_at",Stamp(dt.AddHours(9)),"version","event-test-1","source_ref","synthetic://announcement"));
            }
        }
        for(int d=0;d<dates.Length;d++) {
            DateTime trading=Day(dates[d]);DateTime prior=d>0?Day(dates[d-1]):trading.AddDays(-3);
            W("synthetic/special/derivative-sessions.jsonl",R("contract_id","FUT_A","trading_day",dates[d],"natural_night_start",Stamp(prior.AddHours(21)),"natural_night_end",Stamp(prior.AddDays(1).AddHours(2).AddMinutes(30)),"day_start",Stamp(trading.AddHours(9)),"day_end",Stamp(trading.AddHours(15)),"calendar_version","test_night_calendar","review_status","test_only","available_at",Stamp(day.AddDays(-4))));
        }
        double profileTotal=Enumerable.Range(0,240).Sum(m=>(double)(m<20||m>=220?3:1));
        for(int s=0;s<n;s++)for(int m=0;m<240;m++)
            W("synthetic/models/volume-profile.jsonl",R("security_code",Symbol(s),"slot",m,"weight",(m<20||m>=220?3.0:1.0)/profileTotal,"available_at",Stamp(day.AddDays(-1).AddHours(16)),"profile_source","assumed_prior_not_fitted_history","profile_version","test-profile-v1"));
        W("synthetic/models/execution-parameters.jsonl",R("model_version","synthetic-known-parameters","available_at",Stamp(day.AddDays(-1).AddHours(16)),"adv_proxy_shares",1000000,"adv_history_days",5,"sigma_daily",0.02,"impact_Y",0.8,"temporary_eta",0.0001,"permanent_gamma",0.00001,"risk_lambda",0.01,"queue_models",new[]{"conservative","neutral","optimistic"},"market_calibrated",false));
        W("synthetic/models/evidence-status.jsonl",R("available_at",Stamp(day.AddDays(-1).AddHours(16)),"market_calibration_available",false,"own_queue_position_observed",false,"counterfactual_without_own_orders_observed",false,"raw_feed_completeness","sampled_blocks","calibration_source","not_provided","control_parameters_role","test_assumptions_only"));
        foreach(string variant in new[]{"normal","partial_failure","recovery","missing_evidence"}) {
            string id="SPECIAL-"+variant;
            foreach(string leg in new[]{"FUT_A","FUT_B","OPT_C","OPT_P"})
                W("synthetic/special/derivatives.jsonl",R("scenario_id",id,"variant",variant,"contract_id",leg,"side",leg=="FUT_B"||leg=="OPT_P"?"sell":"buy","multiplier",leg.StartsWith("FUT")?300:10000,"price_tick",leg.StartsWith("FUT")?0.2:0.01,"quote_price",leg.StartsWith("FUT")?4200.0:2.4,"expiry","2026-12-18","trading_day",dates[0],"session_calendar","test_night_calendar","open_close","close_yesterday","position_today",2,"position_yesterday",5,"requested_qty",2,"reported_fill_qty",variant=="partial_failure"?(leg=="FUT_B"||leg=="OPT_P"?0:1):2,"margin_rate",0.12,"delta",leg=="OPT_P"?-0.4:0.6,"gamma",0.02,"vega",0.1,"margin_rule_version","test-margin-1","greeks_version",variant=="missing_evidence"?null:"test-greeks-1","available_at",Stamp(day.AddHours(8))));
            foreach(string venue in new[]{"SYN_X","SYN_Y"})
                W("synthetic/special/overseas-crypto.jsonl",R("scenario_id",id,"variant",variant,"venue",venue,"contract_id","SYNBTC_LINEAR","contract_type","linear","multiplier",0.001,"position_mode","hedge","posSide",venue=="SYN_X"?"long":"short","reduceOnly",false,"currency","USDT","mark_price",50000.0,"balance",10000.0,"position_contracts",variant=="partial_failure"&&venue=="SYN_Y"?0:100,"maintenance_margin_rate",0.005,"funding_rate",0.0001,"funding_published_at",Stamp(day.AddHours(7)),"funding_settled_at",Stamp(day.AddHours(8)),"borrow_rate",variant=="missing_evidence"?(object)null:0.05,"fx_rate",7.1,"cross_border_channel","SYN_TEST_ONLY","quota_total_minor",10000000,"quota_used_minor",1000000,"cash_in_transit_minor",500000,"settlement_delay_days",2,"transfer_status",variant=="recovery"?"confirmed":"pending_review","network","SYN_TEST_NETWORK","quota_weight",1,"available_at",Stamp(day.AddHours(8))));
            for(int s=0;s<n;s++)
                W("synthetic/special/pcf.jsonl",R("scenario_id",id,"variant",variant,"fund_id","SYN_ETF_200","pcf_date",dates[0],"pcf_version","pcf-test-1","available_at",Stamp(day.AddHours(8)),"component_code",Symbol(s),"component_qty",100,"cash_substitution",variant=="missing_evidence"&&s==0?null:new[]{"allowed","mandatory","forbidden"}[s%3],"premium_rate",0.1,"creation_unit",500000,"estimated_cash_minor",100000,"is_real_fund",false));
            W("synthetic/special/etf-events.jsonl",R("scenario_id",id,"variant",variant,"fund_id","SYN_ETF_200","event_type","submission","confirmation_status",variant=="partial_failure"?"rejected":"accepted","event_time",Stamp(day.AddHours(10)),"available_at",Stamp(day.AddHours(10).AddMilliseconds(5)),"actual_cash_adjustment_minor",null));
            W("synthetic/special/etf-events.jsonl",R("scenario_id",id,"variant",variant,"fund_id","SYN_ETF_200","event_type","settlement_update","confirmation_status",variant=="recovery"?"confirmed":"pending","event_time",Stamp(Day(dates[1]).AddHours(16)),"available_at",Stamp(Day(dates[1]).AddHours(16).AddMilliseconds(5)),"actual_cash_adjustment_minor",variant=="recovery"?(object)1000:null));
            W("synthetic/special/block-trades.jsonl",R("scenario_id",id,"variant",variant,"intent_id",id+"-INT","counterparty_id","SYN_CP","holder_identity",variant=="missing_evidence"?null:"synthetic_ordinary_holder","share_origin",variant=="missing_evidence"?null:"test_restricted_batch","security_code","SYN000001","qty",300000,"confirmed_qty",variant=="partial_failure"?300100:300000,"price_ticks",1950,"acquired_at",Stamp(day),"available_at",Stamp(day.AddHours(8)),"restriction_rule_version","test-only-restriction","unlock_at",Stamp(day.AddMonths(6)),"confirmation_id",id+"-CONF","confirmation_status",variant=="partial_failure"?"mismatched":"pending","review_status","test_only"));
        }
    }
    public static string Run(string directory,int seed,int symbols,string[] dates,int quoteInterval) {
        using(var g=new Generator(directory,seed)){g.Market(symbols,dates,quoteInterval);g.Business(symbols,dates);g.Auxiliary(symbols,dates);return g.Catalog();}
    }
}
}
