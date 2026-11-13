using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

namespace TradeInputs {
    // Independent reader of serialized artifacts; never executes the producer's patch code.
    public static class PreciseInputValidator {
        static readonly JavaScriptSerializer J=new JavaScriptSerializer{MaxJsonLength=100000000,RecursionLimit=100};
        static readonly UTF8Encoding U=new UTF8Encoding(false);
        static Dictionary<string,object> O(object x){return (Dictionary<string,object>)x;}
        static object Read(string p){return J.DeserializeObject(File.ReadAllText(p,U));}
        static void Need(bool condition,string message){if(!condition)throw new Exception(message);}
        static int Leaves(object value){if(value is Dictionary<string,object>)return O(value).Values.Sum(v=>Leaves(v));if(value is object[])return ((object[])value).Sum(v=>Leaves(v));return 1;}
        static string H(string text){using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(U.GetBytes(text))).Replace("-", "").ToLowerInvariant();}
        static string FH(string p){using(var h=SHA256.Create())using(var f=File.OpenRead(p))return BitConverter.ToString(h.ComputeHash(f)).Replace("-", "").ToLowerInvariant();}
        static object Copy(object x){return J.DeserializeObject(J.Serialize(x));}
        static string Canon(object x){
            if(x is Dictionary<string,object>)return "{"+String.Join(",",O(x).OrderBy(p=>p.Key,StringComparer.Ordinal).Select(p=>J.Serialize(p.Key)+":"+Canon(p.Value)))+"}";
            if(x is object[])return "["+String.Join(",",((object[])x).Select(Canon))+"]";
            return J.Serialize(x);
        }
        static object At(object root,string path){
            object c=root;foreach(string s in path.Split('/')){
                if(c is Dictionary<string,object>){if(!O(c).ContainsKey(s))throw new KeyNotFoundException(path);c=O(c)[s];}
                else if(c is object[])c=((object[])c)[int.Parse(s)];else throw new KeyNotFoundException(path);
            }return c;
        }
        static bool Exists(object root,string path){try{At(root,path);return true;}catch(KeyNotFoundException){return false;}}
        static double N(object x){Need(x!=null,"Null numeric term");return Convert.ToDouble(x,System.Globalization.CultureInfo.InvariantCulture);}
        static bool SemanticNode(string key){return key=="P02-S01"||key=="P11-S05";}
        static int SlidingPeak(object[] stamps,double width){
            Need(width>0,"Window length must be positive");var ts=stamps.Select(x=>N(x)).OrderBy(x=>x).ToArray();int peak=0,left=0;
            for(int right=0;right<ts.Length;right++){while(ts[right]-ts[left]>=width)left++;peak=Math.Max(peak,right-left+1);}return peak;
        }
        static double[] BidTrace(Dictionary<string,object>[] events,string[] order){
            var lookup=events.ToDictionary(e=>(string)e["event_id"]);var book=new Dictionary<string,Dictionary<string,object>>();var trace=new List<double>();
            foreach(string id in order){Need(lookup.ContainsKey(id),"Unknown replay event");var e=lookup[id];string oid=(string)e["order_id"];
                if((string)e["action"]=="add"){Need(!book.ContainsKey(oid)&&N(e["qty"])>0&&(string)e["side"]=="buy","Invalid bid add");book.Add(oid,e);}
                else {Need((string)e["action"]=="cancel"&&book.ContainsKey(oid),"Unresolved cancel");book.Remove(oid);}
                trace.Add(book.Count==0?0:book.Values.Max(v=>N(v["price_ticks"])));
            }return trace.ToArray();
        }
        static bool ReplayRelation(object payload){
            var events=((object[])At(payload,"events")).Select(O).ToArray();
            var observed=((object[])At(payload,"observed_replay_order")).Cast<string>().ToArray();
            var expected=events.OrderBy(e=>N(e["available_ms"])).Select(e=>(string)e["event_id"]).ToArray();
            Need(events.Select(e=>(string)e["event_id"]).Distinct().Count()==events.Length&&observed.Distinct().Count()==events.Length,"Event identity coverage invalid");
            foreach(var channel in events.GroupBy(e=>Canon(e["channel"])))Need(channel.OrderBy(e=>N(e["available_ms"])).Select(e=>N(e["seq"])).SequenceEqual(channel.Select(e=>N(e["seq"])).OrderBy(x=>x)),"Source local sequence broken");
            var observedTrace=((object[])At(payload,"observed_best_bid_ticks")).Select(N).ToArray();
            var trueTrace=BidTrace(events,expected);var replayTrace=BidTrace(events,observed);
            // Even the faulty trace must be causally produced by its declared replay order.
            Need(observedTrace.SequenceEqual(replayTrace),"Reported book trace not produced by replay");
            var visible=events.Where(e=>N(e["available_ms"])<=N(At(payload,"checkpoint_available_ms"))).OrderBy(e=>N(e["available_ms"])).Select(e=>(string)e["event_id"]).ToArray();
            double best=visible.Length==0?0:BidTrace(events,visible).Last();
            return observed.SequenceEqual(expected)&&observedTrace.SequenceEqual(trueTrace)&&N(At(payload,"observed_checkpoint_best_bid_ticks"))==best;
        }
        static void CheckBatch(object input,string id){
            Need(N(At(input,"symbols"))==200,"Batch universe claim invalid");var days=(object[])At(input,"days");Need(days.Length==5&&days.Select(x=>(string)At(x,"date")).Distinct().Count()==5,"Five batch dates required");
            foreach(var day in days){var req=((object[])At(day,"requests")).Select(O).ToArray();var limits=((object[])At(day,"symbol_limits")).Select(O).ToArray();
                Need(req.Length==200&&req.Select(x=>(string)x["symbol"]).Distinct().Count()==200&&req.Select(x=>(string)x["request_id"]).Distinct().Count()==200,"Actual batch is not 200 unique requests");
                Need(limits.Length==200&&limits.Select(x=>(string)x["symbol"]).Distinct().Count()==200,"Missing per-symbol limits");var lim=limits.ToDictionary(x=>(string)x["symbol"]);
                foreach(var row in req){Need(Canon(row["account_id"])==Canon(At(day,"account_id"))&&Canon(row["target_version"])==Canon(At(day,"target_version"))&&Canon(row["risk_snapshot_version"])==Canon(At(day,"target_version")),"Batch account/version mismatch");
                    Need(lim.ContainsKey((string)row["symbol"])&&N(row["price_ticks"])>0&&N(row["requested_qty"])>0&&N(row["lot_size"])==100&&N(row["available_ms"])>=N(At(day,"available_at_ms")),"Invalid batch request");
                    var limit=lim[(string)row["symbol"]];Need(Canon(limit["account_id"])==Canon(row["account_id"])&&Canon(limit["limit_version"])==Canon(row["target_version"]),"Limit join mismatch");
                    Need(!row.ContainsKey("accepted")&&!row.ContainsKey("allocated_qty"),"Batch contains solved allocation");
                }
                Need(req.Sum(r=>Math.Floor(N(r["requested_qty"])/N(r["lot_size"]))*N(r["lot_size"])*N(r["price_ticks"])+N(r["fee_minor"]))>N(At(day,"cash_available_minor")),"Batch does not trigger cash shortage after rounding");
                if(id=="P04-S06-Q03")Need(req.GroupBy(x=>N(x["available_ms"])).Any(g=>g.Count()>1)&&req.Select(x=>(string)x["worker_id"]).Distinct().Count()>1&&req.Any(r=>N(r["requested_qty"])*N(r["price_ticks"])>N(lim[(string)r["symbol"]]["max_notional_minor"])),"Concurrency/per-stock limit scenario absent");
            }
        }
        static void CheckUnits(Dictionary<string,object> experiments){
            foreach(var entry in experiments){var u=O(At(entry.Value,"_units"));Need(new[]{"integer_ticks","CNY_major","quote_currency_major","contract_quote_major"}.Contains((string)u["default_price_unit"]),"Unknown explicit unit");Need(N(u["price_divisor"])>0&&u.ContainsKey("tick_size")&&(bool)u["explicit_suffixes_override_default"],"Incomplete unit contract");}
        }
        static void CheckImpactUnits(object prices){Need((string)At(prices,"_units/default_price_unit")=="CNY_major"&&N(At(prices,"_units/price_divisor"))==1&&N(At(prices,"_units/tick_size"))==0.01,"Impact path must use CNY major units throughout");}
        static bool Relation(Dictionary<string,object> rule,object payload){
            var terms=(object[])rule["terms"];Func<int,object> t=i=>At(payload,(string)terms[i]);
            switch((string)rule["relation"]){
                case "sliding_window_peak":return N(t(2))==SlidingPeak((object[])t(0),N(t(1)));
                case "channel_book_replay":return ReplayRelation(payload);
                case "equal":return Canon(t(0))==Canon(t(1));
                case "le":return N(t(0))<=N(t(1));
                case "lt":return N(t(0))<N(t(1));
                case "true":return t(0) is bool&&(bool)t(0);
                case "false":return t(0) is bool&&!(bool)t(0);
                case "zero":return N(t(0))==0;
                case "budget":return Math.Abs(N(t(0))-Enumerable.Range(1,terms.Length-1).Sum(i=>N(t(i))))<1e-9;
                case "sum_le":return ((object[])t(0)).Sum(x=>N(x))<=N(t(1));
                case "count_le":return ((object[])t(0)).Length<=N(t(1));
                case "capacity":var a=(object[])t(0);var b=(object[])t(1);return a.Length==b.Length&&Enumerable.Range(0,a.Length).All(i=>N(a[i])>=0&&N(a[i])<=N(b[i]));
                case "disjoint":return !((object[])t(0)).Select(Canon).Intersect(((object[])t(1)).Select(Canon)).Any();
                case "ledger":return Math.Abs(N(t(0))+((object[])t(1)).Sum(x=>N(x))-N(t(2)))<1e-9;
                default:throw new Exception("Unknown independent relation");
            }
        }
        static void NoAnswers(object x){
            if(x is Dictionary<string,object>)foreach(var p in O(x)){Need(!new[]{"answer","expected_output","solution","teacher_response"}.Contains(p.Key),"Answer field prohibited");NoAnswers(p.Value);}
            else if(x is object[])foreach(var v in (object[])x)NoAnswers(v);
        }
        static Dictionary<string,object> Lines(string p){var d=new Dictionary<string,object>();foreach(string l in File.ReadLines(p,U)){if(String.IsNullOrWhiteSpace(l))continue;var x=O(J.DeserializeObject(l));d.Add((string)x["node"],x);}return d;}
        static void CheckQuestion(Dictionary<string,object> c,Dictionary<string,object> q,Dictionary<string,object> recipe){
            Need((string)c["question_id"]==(string)q["question_id"],"Question/case association changed");
            Need((string)c["node_key"]==(string)q["split_group_id"],"Node association changed");
            Need((string)c["question_sha256"]==H((string)q["question"]),"Stale question text binding");
            Need((string)c["source_class"]=="synthetic_test_only","False source fidelity");NoAnswers(c);
            string qid=(string)q["question_id"];int n=int.Parse(qid.Substring(qid.Length-2));
            if(n<=5){var ex=O(recipe["experiments"]).Single(p=>p.Key.StartsWith("q"+n+"_",StringComparison.Ordinal));var small=O(c["small_case"]);Need((string)small["experiment_id"]==ex.Key&&Canon(small["given"])==Canon(ex.Value),"Question-specific input projection mismatch");Need(Leaves(ex.Value)>=2,"Insufficient question-specific givens: "+qid);}
            if(n==6||n==10){Need(!Exists(At(c,"small_case/experiments"),(string)recipe["missing"]),"Essential evidence was not removed");}
        }
        static void Rejected(Action test,string label,List<string> results){bool rejected=false;try{test();}catch{rejected=true;}Need(rejected,"Negative case accepted: "+label);results.Add(label);}
        public static string Validate(string repo,string data,string output,bool selfTest){
            var recipes=Lines(Path.Combine(repo,"config/precise-node-inputs.jsonl"));foreach(var p in Lines(Path.Combine(repo,"config/precise-node-inputs-extra.jsonl")))recipes.Add(p.Key,p.Value);
            var probes=Lines(Path.Combine(repo,"config/node-fault-probes.jsonl"));
            var questions=File.ReadLines(Path.Combine(output,"交易执行_教师输入.jsonl"),U).Where(x=>!String.IsNullOrWhiteSpace(x)).Select(x=>O(J.DeserializeObject(x))).ToDictionary(x=>(string)x["question_id"]);
            var catalog=O(Read(Path.Combine(data,"case-manifest.json")));var index=new Dictionary<string,Dictionary<string,object>>();
            foreach(var x in (object[])catalog["files"]){var f=O(x);string rel=(string)f["path"];Need(!rel.Contains("..")&&!Path.IsPathRooted(rel)&&rel.StartsWith("cases/",StringComparison.Ordinal)&&!rel.Contains("_internal"),"Unsafe case path");Need(FH(Path.Combine(data,rel))==(string)f["sha256"],"Case hash mismatch: "+rel);index.Add(rel,f);}
            Need(index.Count==1725&&questions.Count==1150&&probes.Count==115&&recipes.Count==115,"Precise input coverage mismatch");
            var nodeRows=new List<object>();var questionRows=new List<object>();var negatives=new List<string>();
            foreach(var key in recipes.Keys.OrderBy(x=>x)){
                var r=O(recipes[key]);var p=O(probes[key]);
                CheckUnits(O(r["experiments"]));
                Func<string,Dictionary<string,object>> variant=v=>O(Read(Path.Combine(data,"cases/nodes/"+key+"/"+v+".json")));
                var normal=O(variant("normal")["input"]);var fault=O(variant("fault")["input"]);var recovery=O(variant("recovery")["input"]);var missing=O(variant("missing_evidence")["input"]);var neutral=O(variant("neutral_representation")["input"]);
                foreach(var v in new[]{"normal","fault","recovery","missing_evidence","neutral_representation"}){var content=variant(v);Need((string)content["node_key"]==key&&(string)content["variant"]==v&&(string)content["source_class"]=="synthetic_test_only","Variant identity mismatch");NoAnswers(content);Need(index.ContainsKey("cases/nodes/"+key+"/"+v+".json"),"Uncatalogued node input");}
                Need(Canon(normal["experiments"])==Canon(r["experiments"]),"Node normal inputs differ from authored recipe");
                Need(Canon(normal["diagnostic_observation"])==Canon(p["given"]),"Node probe differs from authored observations");
                Need(Relation(p,normal["diagnostic_observation"]),"Normal relation invalid: "+key);
                Need(!Relation(p,fault["diagnostic_observation"]),"Fault has no independent violation: "+key);
                Need(Canon(recovery["diagnostic_observation"])==Canon(fault["diagnostic_observation"]),"Recovery exported a solved final state: "+key);
                Need(O(recovery["recovery_evidence"]).Count==2&&Canon(At(recovery,"recovery_evidence/diagnostic_query"))==Canon(p["recovery"]),"Recovery query evidence missing");
                Need(Canon(normal)==Canon(neutral),"Neutral representation changed business semantics");
                string missingPath="experiments/"+(string)r["missing"];Need(Exists(normal,missingPath)&&At(normal,missingPath)!=null&&!Exists(missing,missingPath),"Missing-evidence case did not remove known substantive field: "+key);
                int changes=0;foreach(var patch in O(r["fault"])){string path="experiments/"+patch.Key;Need(Exists(normal,path)&&Canon(At(fault,path))==Canon(patch.Value),"Authored numeric/message fault missing");if(Canon(At(normal,path))!=Canon(At(fault,path)))changes++;}
                Need(changes>0,"Recipe fault only labels metadata: "+key);
                foreach(var patch in O(p["fault"]))Need(Canon(At(fault,"diagnostic_observation/"+patch.Key))==Canon(patch.Value),"Probe fault mismatch");
                nodeRows.Add(new{node_key=key,question_count=10,explicit_question_experiments=5,node_variants=5,normal_relation="passed",fault_relation="violation_detected",recovery_evidence="raw_queries_only_no_solved_final_state",missing_field=missingPath,neutral_semantics="unchanged",independent_relation=p["relation"],structure_validated=true,semantic_status=SemanticNode(key)?"raw_event_oracle_verified":"pending_semantic_review",exact_node_fault_implemented=SemanticNode(key)});
            }
            foreach(var q in questions.Values.OrderBy(x=>(string)x["question_id"])){
                string id=(string)q["question_id"],key=(string)q["split_group_id"],rel="cases/questions/"+id+".json";Need(index.ContainsKey(rel),"Missing question case");var c=O(Read(Path.Combine(data,rel)));CheckQuestion(c,q,O(recipes[key]));
                foreach(var item in (object[])c["scenario_files"]){var f=O(item);string path=(string)f["path"];Need(index.ContainsKey(path)&&(string)index[path]["sha256"]==(string)f["sha256"]&&path.StartsWith("cases/nodes/"+key+"/",StringComparison.Ordinal),"Question scenario association mismatch");}
                int qn=int.Parse(id.Substring(id.Length-2));
                if(qn<=5)Need(((object[])c["scenario_files"]).Length==0,"First-five question exposed another question's diagnostic observations");
                if(qn==8){var faultInput=At(Read(Path.Combine(data,"cases/nodes/"+key+"/fault.json")),"input");Need(Canon(At(c,"small_case/diagnostic_observation"))==Canon(At(faultInput,"diagnostic_observation"))&&Canon(At(c,"small_case/experiment_inputs"))==Canon(At(faultInput,"experiments")),"Diagnosis case did not project actual faulty input");}
                if(qn==7||qn==9)Need(Canon(At(c,"small_case/experiments"))==Canon(O(recipes[key])["experiments"]),"Implementation/metamorphic question lost node inputs");
                questionRows.Add(new{question_id=id,node_key=key,case_file=rel,case_sha256=index[rel]["sha256"],question_sha256=c["question_sha256"],adaptation_role=c["adaptation_role"],source_class="synthetic_test_only",question_specific_input_validated=true,validation_scope="projection_and_declared_contract; see node semantic_status",exact_node_fault_implemented=SemanticNode(key),real_dataset_ready=false});
            }
            // Cross-check literal anchors from the actual question wording, not generated metadata.
            Func<string,object> given=id=>At(Read(Path.Combine(data,"cases/questions/"+id+".json")),"small_case/given");
            Need(N(At(given("P01-S01-Q02"),"target_buy_qty"))==1000&&N(At(given("P01-S01-Q02"),"pending_buy_qty"))==400,"Literal 1000/400 question drift");
            Need(N(At(given("P03-S04-Q02"),"target"))==1000,"IS literal target drift");
            Need(N(At(given("P04-S06-Q03"),"symbols"))==200,"Universe literal drift");
            CheckBatch(given("P01-S01-Q04"),"P01-S01-Q04");CheckBatch(given("P04-S06-Q03"),"P04-S06-Q03");
            var prices=given("P02-S02-Q03");CheckImpactUnits(prices);Need(N(At(prices,"arrival"))==20,"Impact arrival price drifted");
            Need(At(given("P05-S08-Q05"),"nic_rx_timestamp")==null&&!(bool)At(given("P05-S08-Q05"),"hardware_evidence"),"Synthetic hardware false claim");
            Need(At(given("P13-S01-Q03"),"actual_pcf_quantities") is object[],"Weights substituted for PCF");
            var links=given("P02-S01-Q01");var orders=(object[])At(links,"orders");var trades=(object[])At(links,"trades");var ids=new HashSet<string>(orders.Select(x=>Canon(At(x,"exchange_id"))));
            bool idsDistinct=orders.All(x=>Canon(At(x,"local_id"))!=Canon(At(x,"exchange_id")));
            bool refsResolved=trades.All(x=>ids.Contains(Canon(At(x,"bid_exchange_id")))&&ids.Contains(Canon(At(x,"ask_exchange_id"))));
            Need(idsDistinct&&refsResolved,"Order linkage relies on equal local/exchange IDs or unresolved refs");
            Need(((object[])At(given("P02-S02-Q02"),"own_parent_ids")).Length==0,"Missing-own-orders question accidentally includes ownership evidence");
            Need(N(At(given("P02-S06-Q02"),"ask_qty"))==0&&N(At(given("P02-S06-Q02"),"capacity"))==0,"Sealed-market question accidentally has executable ask liquidity");
            Need(At(given("P03-S01-Q05"),"decision_record_id")==null,"Missing-decision question includes a decision record");
            Need(N(At(given("P02-S04-Q05"),"synthetic_generation_parameters/risk_lambda"))==0&&((object[])At(given("P02-S04-Q05"),"synthetic_inventory")).Length==6,"Known-lambda synthetic recovery experiment missing");
            if(selfTest){
                var original=O(Read(Path.Combine(data,"cases/questions/P01-S01-Q02.json")));var q=questions["P01-S01-Q02"];var r=O(recipes["P01-S01"]);
                var bad=O(Copy(original));bad["question_id"]="P02-S01-Q02";Rejected(()=>CheckQuestion(bad,q,r),"wrong_question_case",negatives);
                bad=O(Copy(original));bad["question_sha256"]="stale";Rejected(()=>CheckQuestion(bad,q,r),"stale_question_hash",negatives);
                bad=O(Copy(original));O(At(bad,"small_case/given"))["pending_buy_qty"]=200;Rejected(()=>CheckQuestion(bad,q,r),"literal_quantity_mismatch",negatives);
                bad=O(Copy(original));bad["answer"]="prohibited";Rejected(()=>CheckQuestion(bad,q,r),"answer_leakage",negatives);
                bad=O(Copy(original));bad["source_class"]="real";Rejected(()=>CheckQuestion(bad,q,r),"false_real_source",negatives);
                var probe=O(probes["P01-S08"]);Rejected(()=>Need(Relation(probe,O(probe["given"]).ToDictionary(x=>x.Key,x=>x.Key=="journal_fill_qty"?(object)1200:x.Value)),"duplicate ledger accepted"),"triple_counted_fill",negatives);
                probe=O(probes["P05-S06"]);var pp=O(Copy(probe["given"]));pp["accepted_costs_minor"]=new object[]{60000,60000};Rejected(()=>Need(Relation(probe,pp),"over reservation accepted"),"concurrent_cash_overrun",negatives);
                probe=O(probes["P09-S01"]);pp=O(Copy(probe["given"]));pp["observed_first_read_ms"]=900000;Rejected(()=>Need(Relation(probe,pp),"future read accepted"),"future_feature_read",negatives);
                probe=O(probes["P13-S03"]);pp=O(Copy(probe["given"]));pp["accepted_reservations"]=new object[]{700,700};Rejected(()=>Need(Relation(probe,pp),"double basket reservation accepted"),"duplicate_basket_reservation",negatives);
                probe=O(probes["P11-S05"]);pp=O(Copy(probe["given"]));pp["events_ms"]=new object[]{0,2000,4000,6000};pp["reported_peak"]=4;pp["independent_sliding_peak"]=4;Rejected(()=>Need(Relation(probe,pp),"fabricated matching peaks accepted"),"matching_peaks_disagree_with_events",negatives);
                Need(SlidingPeak(new object[]{0,999,1000,1999},1000)==2&&SlidingPeak(new object[]{0,0,1000},1000)==2,"Half-open window boundary incorrect");
                probe=O(probes["P02-S01"]);pp=O(Copy(probe["given"]));pp["observed_replay_order"]=new object[]{"ADD_B","ADD_A","CANCEL_A"};pp["observed_best_bid_ticks"]=new object[]{101,101,101};pp["observed_checkpoint_best_bid_ticks"]=101;Rejected(()=>Need(Relation(probe,pp),"global seq sort accepted"),"global_sequence_sort_preserves_local_order_but_changes_book",negatives);
                pp=O(Copy(given("P01-S01-Q04")));O(((object[])pp["days"])[0])["requests"]=((object[])At(pp,"days/0/requests")).Take(2).ToArray();Rejected(()=>CheckBatch(pp,"P01-S01-Q04"),"claimed_200_but_only_two_orders",negatives);
                pp=O(Copy(given("P04-S06-Q03")));O(At(pp,"days/0/requests/0"))["account_id"]="WRONG_ACCOUNT";Rejected(()=>CheckBatch(pp,"P04-S06-Q03"),"batch_account_join_mismatch",negatives);
                Need(N((object)20)/N(At(prices,"_units/price_divisor"))==N((object)20.0)/N(At(prices,"_units/price_divisor")),"Numeric representation changed price units");
                pp=O(Copy(prices));O(pp["_units"])["price_divisor"]=100;Rejected(()=>CheckImpactUnits(pp),"major_price_misread_as_ticks",negatives);
            }
            var report=new{result="passed",scope="synthetic_question_specific_inputs_only",nodes=115,questions=1150,explicit_first_five_experiments=575,node_variant_files=575,question_case_files=1150,case_files_hash_checked=index.Count,validation_schema_version=3,declared_relations_checked=115,raw_event_oracles_verified=2,semantic_pending_nodes=113,verified_batch_questions=2,explicit_unit_contracts_checked=575,fault_relations_violated=115,recovery_observations_checked=115,missing_evidence_cases=115,neutral_semantics_checked=115,literal_anchors_checked=10,negative_cases_rejected=negatives.ToArray(),answers_generated=0,real_dataset_ready=false,real_calibration_ready=false,nodes_detail=nodeRows.ToArray(),questions_detail=questionRows.ToArray(),recipe_hashes=new[]{"precise-node-inputs.jsonl","precise-node-inputs-extra.jsonl","node-fault-probes.jsonl","question-scenario-selection.jsonl"}.ToDictionary(x=>x,x=>FH(Path.Combine(repo,"config",x))),case_manifest_sha256=FH(Path.Combine(data,"case-manifest.json"))};
            string result=J.Serialize(report)+"\n";File.WriteAllText(Path.Combine(data,"precise-validation.json"),result,U);File.WriteAllText(Path.Combine(output,"precise-input-validation.json"),result,U);
            return J.Serialize(new{result="passed",nodes=115,questions=1150,case_files=index.Count,negative_cases_rejected=negatives.Count});
        }
    }
}
