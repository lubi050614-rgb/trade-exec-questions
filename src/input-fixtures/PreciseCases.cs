using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Web.Script.Serialization;

namespace TradeInputs {
    // Produces input fixtures only. Validation rules live in the independent validator.
    public static class PreciseCases {
        static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 100000000, RecursionLimit = 100 };
        static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);
        static Dictionary<string,object> Obj(object x) { return (Dictionary<string,object>)x; }
        static object Clone(object x) { return Json.DeserializeObject(Json.Serialize(x)); }
        static Dictionary<string,object> D(params object[] kv) {
            var d = new Dictionary<string,object>(); for(int i=0;i<kv.Length;i+=2)d.Add((string)kv[i],kv[i+1]);return d;
        }
        public static string HashText(string text) { using(var s=SHA256.Create())return BitConverter.ToString(s.ComputeHash(Utf8.GetBytes(text))).Replace("-", "").ToLowerInvariant(); }
        static string FileHash(string path) { using(var s=SHA256.Create())using(var f=File.OpenRead(path))return BitConverter.ToString(s.ComputeHash(f)).Replace("-", "").ToLowerInvariant(); }
        static void Patch(object root,string path,object value,bool remove) {
            var parts=path.Split('/'); object cursor=root;
            for(int i=0;i<parts.Length-1;i++) cursor=cursor is IDictionary<string,object>?Obj(cursor)[parts[i]]:((IList)cursor)[int.Parse(parts[i])];
            string last=parts[parts.Length-1];
            if(cursor is IDictionary<string,object>) {var d=Obj(cursor);if(!d.ContainsKey(last))throw new Exception("Unknown patch path: "+path);if(remove)d.Remove(last);else d[last]=Clone(value);}
            else {if(remove)throw new Exception("Array deletion prohibited");((IList)cursor)[int.Parse(last)]=Clone(value);}
        }
        static object Reverse(object x) {
            if(x is Dictionary<string,object>){var d=new Dictionary<string,object>();foreach(var p in Obj(x).Reverse())d.Add(p.Key,Reverse(p.Value));return d;}
            if(x is object[])return ((object[])x).Select(Reverse).ToArray();return x;
        }
        static Dictionary<string,object> ReadLines(string path) {
            var result=new Dictionary<string,object>();foreach(var line in File.ReadLines(path,Utf8)){if(String.IsNullOrWhiteSpace(line))continue;var r=Obj(Json.DeserializeObject(line));result.Add((string)r["node"],r);}return result;
        }
        public static string Build(string repo,string data,string questionPath,string nodesPath) {
            var recipes=ReadLines(Path.Combine(repo,"config/precise-node-inputs.jsonl"));
            foreach(var p in ReadLines(Path.Combine(repo,"config/precise-node-inputs-extra.jsonl")))recipes.Add(p.Key,p.Value);
            var probes=ReadLines(Path.Combine(repo,"config/node-fault-probes.jsonl"));
            var sharedManifest=Obj(Json.DeserializeObject(File.ReadAllText(Path.Combine(data,"manifest.json"),Utf8)));
            var nodes=((object[])Json.DeserializeObject(File.ReadAllText(nodesPath,Utf8))).Select(Obj).ToDictionary(x=>(string)x["node_key"]);
            if(recipes.Count!=115||probes.Count!=115||!recipes.Keys.OrderBy(x=>x).SequenceEqual(nodes.Keys.OrderBy(x=>x))||!probes.Keys.OrderBy(x=>x).SequenceEqual(nodes.Keys.OrderBy(x=>x)))throw new Exception("Explicit recipe/probe coverage must be exactly 115 nodes");
            var files=new List<object>();var refs=new Dictionary<string,object>();
            Action<string,object> write=(relative,value)=>{string path=Path.Combine(data,relative);Directory.CreateDirectory(Path.GetDirectoryName(path));File.WriteAllText(path,Json.Serialize(value)+"\n",Utf8);files.Add(D("path",relative,"sha256",FileHash(path)));};
            foreach(var key in nodes.Keys.OrderBy(x=>x)) {
                var r=Obj(recipes[key]);var p=Obj(probes[key]);var ex=Obj(r["experiments"]);
                for(int q=1;q<=5;q++)if(ex.Keys.Count(k=>k.StartsWith("q"+q+"_",StringComparison.Ordinal))!=1)throw new Exception("Each first-five question needs one explicit experiment: "+key);
                if(ex.Count!=5)throw new Exception("Unexpected experiments: "+key);
                var normal=D("experiments",Clone(ex),"diagnostic_observation",Clone(p["given"]));
                var fault=Obj(Clone(normal));foreach(var patch in Obj(r["fault"]))Patch(fault,"experiments/"+patch.Key,patch.Value,false);
                foreach(var patch in Obj(p["fault"]))Patch(fault,"diagnostic_observation/"+patch.Key,patch.Value,false);
                // Preserve the faulty local observation. Queries are additional inputs, never a solved final state.
                var recovery=Obj(Clone(fault));recovery["recovery_evidence"]=D("experiment_query",Clone(r["recovery"]),"diagnostic_query",Clone(p["recovery"]));
                var missing=Obj(Clone(normal));Patch(missing,"experiments/"+(string)r["missing"],null,true);
                missing["missing_paths"]=new[]{"experiments/"+(string)r["missing"]};
                var variants=D("normal",normal,"fault",fault,"recovery",recovery,"missing_evidence",missing,"neutral_representation",Reverse(normal));
                var scenarioRefs=new List<object>();
                foreach(var v in variants) {
                    string rel="cases/nodes/"+key+"/"+v.Key+".json";
                    var payload=D("schema_version","2.0","node_key",key,"variant",v.Key,"source_class","synthetic_test_only","input",v.Value,"unit_policy","suffixes _ms/_ns/_ticks/_minor are literal units; unqualified prices/amounts use each experiment's explicit unit/spec; quantities remain instrument-specific","availability_policy","independent offline test timelines; each decision may use only observations delivered by that decision; missing timestamps do not imply preopen availability","failure_scenario",nodes[key]["failure_scenario"],"no_answers",true);
                    write(rel,payload);scenarioRefs.Add(D("variant",v.Key,"path",rel,"sha256",FileHash(Path.Combine(data,rel))));
                }
                refs.Add(key,scenarioRefs.ToArray());
            }
            var allQuestions=File.ReadLines(questionPath,Utf8).Where(x=>!String.IsNullOrWhiteSpace(x)).Select(x=>Obj(Json.DeserializeObject(x))).ToArray();
            foreach(var q in allQuestions) {
                string id=(string)q["question_id"],key=(string)q["split_group_id"];int number=int.Parse(id.Substring(id.Length-2));var r=Obj(recipes[key]);var ex=Obj(r["experiments"]);
                object primary;string role;string[] variants;
                if(number<=5){var e=ex.Single(x=>x.Key.StartsWith("q"+number+"_",StringComparison.Ordinal));primary=D("experiment_id",e.Key,"given",Clone(e.Value));role="question_specific_literal_inputs";variants=new string[0];}
                else if(number==6||number==10){primary=D("experiments",Clone(ex),"missing_paths",new[]{(string)r["missing"]});Patch(primary,"experiments/"+(string)r["missing"],null,true);role="missing_evidence_and_source_boundary";variants=new[]{"missing_evidence"};}
                else if(number==8){var p=Obj(probes[key]);var observation=Obj(Clone(p["given"]));foreach(var patch in Obj(p["fault"]))Patch(observation,patch.Key,patch.Value,false);primary=D("diagnostic_observation",observation,"experiment_inputs",Clone(ex));foreach(var patch in Obj(r["fault"]))Patch(primary,"experiment_inputs/"+patch.Key,patch.Value,false);role="fault_diagnosis_observations";variants=new[]{"fault","recovery"};}
                else {primary=D("experiments",Clone(ex));role=number==9?"semantic_invariance_and_fault_comparison":"implementation_contract_inputs";variants=number==9?new[]{"normal","neutral_representation","fault"}:new[]{"normal","recovery"};}
                var available=(object[])refs[key];var selected=available.Select(Obj).Where(x=>variants.Contains((string)x["variant"])).ToArray();
                var caseValue=D("schema_version","2.0","question_id",id,"node_key",key,"question_sha256",HashText((string)q["question"]),"source_class","synthetic_test_only","adaptation_role",role,"small_case",primary,"scenario_files",selected,"large_context",D("n_symbols",sharedManifest["actual_n_symbols"],"n_days",sharedManifest["actual_n_days"],"role","separate_shared_stress_context_do_not_merge_small_case_quantities"),"unit_policy","Each experiment _units declares a stable default_price_unit, price_divisor and tick_size. Explicit field suffixes/specifications override defaults. Integer versus floating representation never changes units. A missing required unit/spec remains unknown; do not infer it from defaults.","availability_policy","offline diagnostic timelines; future observations are for chronological reasoning, never a live feature snapshot; unknown delivery time remains unknown","unknown_real_evidence",q["missing_data_ids"],"no_answers",true);
                write("cases/questions/"+id+".json",caseValue);
            }
            var manifest=D("schema_version","2.0","generator","explicit_per_question_recipes","node_count",115,"question_count",allQuestions.Length,"node_variants",575,"question_cases",1150,"files",files.ToArray(),"recipe_sources",new[]{"config/precise-node-inputs.jsonl","config/precise-node-inputs-extra.jsonl","config/node-fault-probes.jsonl"},"source_class","synthetic_test_only","answers_generated",0);
            File.WriteAllText(Path.Combine(data,"case-manifest.json"),Json.Serialize(manifest)+"\n",Utf8);
            return Json.Serialize(D("node_variants",575,"question_cases",allQuestions.Length,"catalog_files",files.Count));
        }
    }
}
