(********************************************************
* Arbogen-lib : fast uniform random generation of trees *
*********************************************************
* Module: Gen                                           *
* -------                                               *
* The Boltzmann random generator                        *
* -------                                               *
* (C) 2011, Xuming Zhan, Frederic Peschanski            *
*           Antonine Genitrini, Matthieu Dien           *
*           under the                                   *
*           GNU GPL v.3 licence (cf. LICENSE file)      *
*********************************************************)

open Printf

open Options
open Tree
open Util
open CombSys
open WeightedGrammar
open OracleSimple
open Grammar



let rec find_component (rdm_float:float) componentList = 
  match componentList with
    | [comp] -> comp
    | comp::list_comp -> let (composant,freq) = comp in
			 if rdm_float <= freq then
                           comp
			 else
                           find_component (rdm_float-.freq) list_comp
    | _ -> failwith "find_component failed !!!" 

let rec get_next_rule (name_rule:string) (wgrm:WeightedGrammar.weighted_grammar) (isCall:bool) =      
  let (total_weight,component_list) = (StringMap.find name_rule wgrm) in
  let rdm_float = Random.float total_weight in
  let comp = (find_component rdm_float component_list) in
  match comp with
    | (Grammar.Call elem), _ -> get_next_rule elem wgrm true
    | (Grammar.Cons( w, elem_list)), _ ->
      begin
      (w, 
       List.fold_left 
	 (fun next_rules elem ->
           match elem with
             | (Grammar.Elem name) -> name :: next_rules
             | (Grammar.Seq name) -> let (w,_) = StringMap.find name_rule wgrm in
                                     let n' = int_of_float (floor((log( Random.float 1.)) /. (log w))) in
                                     next_rules @ (concat_n [name] (n'-1))
	 )
	 []
	 elem_list,isCall)
  end
      

let rec init_counter (g:grammar) map =
  match g with
    | [] -> map 
    | rul::rules -> init_counter rules (StringMap.add (fst rul) 0 map)  
    
let rec count_rules counters elements =
  match elements with 
  |elem::elems -> let nb = StringMap.find elem counters in
                  let new_map = StringMap.add elem (nb+1) counters in
                  count_rules new_map elems;
  | _ -> counters

let  find_non_zero counters =
  let filterd_map = StringMap.filter (fun _ n -> n <> 0) counters in
  if StringMap.is_empty filterd_map then
    None
  else
    Some(fst (StringMap.choose filterd_map))

let rec sim(size:int) counters (wgrm:WeightedGrammar.weighted_grammar) (sizemax:int) (current_rule:string) =
  if (size>sizemax)  then
    size
  else
    begin
    let(_,_) = (StringMap.find current_rule wgrm) in 
    let (total_weight,next_rules,isCall) = get_next_rule current_rule wgrm false in
    if (List.length next_rules) > 0 then 
      begin
      let new_counters = (count_rules counters (List.tl next_rules)) in 
        sim (size+total_weight) new_counters wgrm sizemax  (List.hd next_rules)
       end 
    else
      begin
      let non_zero = find_non_zero counters in
      match non_zero with
      | Some s ->let nb = StringMap.find s counters in        
                  let new_nb = nb - 1 in
                     sim (size+total_weight) (StringMap.add s new_nb counters) wgrm sizemax s      
      | None -> (size+total_weight)
      end
    end



let rec simulate_seed (wgrm:WeightedGrammar.weighted_grammar) (grm:grammar) (nb_try:int) (nb_smaller:int) (nb_bigger:int) (sizemin:int) (sizemax:int)  =
  if nb_try > 0 then
    let counters = init_counter grm StringMap.empty in
    let (first_rule,_) = List.hd grm in 
    let res = sim 0 counters wgrm sizemax first_rule in
    if res < sizemin then
      begin
        simulate_seed wgrm grm (nb_try - 1)  (nb_smaller+1) nb_bigger sizemin sizemax
      end
    else if res > sizemax then
      begin
        simulate_seed wgrm grm (nb_try - 1)  nb_smaller (nb_bigger+1) sizemin sizemax
      end
    else
      (Some(res),nb_smaller,nb_bigger)
    else
      (None,nb_smaller,nb_bigger)

let rec simulator_aux (wgrm:WeightedGrammar.weighted_grammar) (grm:grammar) (nb_change_seed:int) (nb_try:int) (nb_smaller:int) (nb_bigger:int) = 
  if nb_change_seed > 0 then
    let (size,new_nb_smaller,new_nb_bigger) = simulate_seed wgrm grm nb_try 0 0 nb_smaller nb_bigger in
    match size with
    | Some size -> (Some(size),(new_nb_smaller+nb_smaller),(nb_bigger+new_nb_bigger)) 
    | None -> simulator_aux wgrm grm (nb_change_seed - 1) nb_try (new_nb_smaller+nb_smaller) (nb_bigger+new_nb_bigger)
  else
    (None,nb_smaller,nb_bigger)

let rec simulator nb_refine_seed nb_change_seed nb_try g epsilon1 epsilon2 zmin zmax zstart epsilon1_factor epsilon2_factor sys sizemin sizemax ratio_rejected seed= 
  let (zmin',zmax',y) = 
    (if global_options.verbosity >= 2
     then printf "[ORACLE]: search singularity at z=%f\n%!" zstart) ;
    searchSingularity sys zmin zmax epsilon1 epsilon2 zstart in
  (if global_options.verbosity >= 2
   then printf "          ==> found singularity at z=%f\n%!" zmin');
  let wgrm = weighted_grm_of_grm g y in     
  let (size,nb_smaller,nb_bigger) = simulator_aux wgrm g nb_change_seed nb_try sizemin sizemax in
  match size with
  | Some size -> Some(size,seed,wgrm)
  | None  -> if nb_refine_seed > 0 then
            begin
              if (float_of_int nb_smaller) /. (float_of_int (nb_smaller+nb_bigger)) >= ratio_rejected then
                 simulator (nb_refine_seed - 1)  nb_change_seed nb_try g (epsilon1 *. epsilon1_factor) (epsilon2 *. epsilon2_factor) zmin' zmax'  zstart epsilon1_factor epsilon2_factor sys sizemin sizemax ratio_rejected seed
              else
                 let new_seed = Random.int 11231231 in
                    Random.init new_seed;
                    simulator (nb_refine_seed - 1)  nb_change_seed nb_try g (epsilon1 *. epsilon1_factor) (epsilon2 *. epsilon2_factor) zmin' zmax'  zstart epsilon1_factor epsilon2_factor sys sizemin sizemax  ratio_rejected new_seed         
            end
            else
              None 

type 'a queue = 'a Queue.t

let rec gen_tree_stack (size:int) counters (wgrm:WeightedGrammar.weighted_grammar) (sizemax:int) (current_rule:string) rules=
  if (size>sizemax) then
    (Stack.create () , 0)
  else
      begin
	let(_,_) = (StringMap.find current_rule wgrm) in 
	let (total_weight,next_rules,_) = get_next_rule current_rule wgrm false in
	Stack.push (current_rule,(List.length next_rules),total_weight) rules;
	if (List.length next_rules) > 0 then
          let new_counters = (count_rules counters (List.tl next_rules)) in  
          gen_tree_stack (size+total_weight) new_counters wgrm sizemax  (List.hd next_rules) rules
	else
          begin
	    let non_zero = find_non_zero counters in
	    match non_zero with
	      | Some s ->let nb = StringMap.find s counters in        
			 let new_nb = nb - 1 in
			 gen_tree_stack (size+total_weight) (StringMap.add s new_nb counters) wgrm sizemax s rules      
	      | None -> (rules,(size+total_weight))
	  end
      end

let rec try_tree_stack (wgrm:WeightedGrammar.weighted_grammar) (grm:grammar) (nb_try:int) (sizemin:int) (sizemax:int)  =
  if nb_try > 0 then
    let counters = init_counter grm StringMap.empty in
    let (first_rule,_) = List.hd grm in 
    let (rules,res) = gen_tree_stack 0 counters wgrm sizemax first_rule (Stack.create ()) in
    if res < sizemin then
      begin
        try_tree_stack wgrm grm (nb_try - 1) sizemin sizemax
      end
    else if res > sizemax then
      begin
        try_tree_stack wgrm grm (nb_try - 1) sizemin sizemax
      end
    else
      Some(rules,res)
    else
      None




let rec aux_rec
    (stack,size)
    (current_rules: tree queue)
    (with_prefix:bool) (idprefix:string) =
  match (Stack.is_empty stack) with
  |true -> ()
  |false -> let prefix = if with_prefix then idprefix ^ (string_of_int (size)) else (string_of_int (size)) in
	    let (rule,arity,_) = Stack.pop stack in
	    let next_rule = 
	      if arity=0 then
		Leaf(rule,prefix)
	      else
		let sons = npop arity current_rules in Node(rule,prefix,sons)
	    in
	    Queue.push next_rule current_rules;
	    aux_rec (stack,size-1) current_rules with_prefix idprefix

let aux
    (stack,size)
    (with_prefix:bool) (idprefix:string) =
  let queue = Queue.create () in
  match size with
  | 0 -> (None,0)
  | _ -> aux_rec (stack,size) queue with_prefix idprefix;
    (Some(Queue.pop queue),size)

let generator
    (g:grammar)
    (self_seed:bool)
    (seed:int)
    (sizemin:int)
    (sizemax:int)
    (epsilon1:float)
    (epsilon1_factor:float)
    (epsilon2:float)
    (epsilon2_factor:float)
    (max_try:int)
    (ratio_rejected:float)
    (max_refine:int)
    (max_refine_seed:int)
    (zstart:float)
    =
   let seed2 =  
   if self_seed then 
     begin
     Random.self_init ();
     Random.int 11231231;                  
     end
   else
    seed 
  in
  Random.init seed2;
  printf "seed = %d\n" seed2;
  let sys = combsys_of_grammar (completion g) in
  (if global_options.verbosity >= 2
   then printf "[GEN]: combinatorial system is:\n%s\n%!" (fst (string_of_combsys sys))
  ); 
  let res = simulator max_refine max_refine_seed max_try g epsilon1 epsilon2 0. 1. zstart epsilon1_factor epsilon2_factor sys sizemin sizemax ratio_rejected seed in
  match res with 
  | Some(final_size,seed,wgrm) -> begin
                                  printf "J'ai trouve %d \n" final_size; printf "With seed %d\n" seed;
                                  Random.init seed;
                                  let final = try_tree_stack wgrm g 1000 sizemin sizemax in
                                  match final with
                                  | Some(rules,res) -> let x  = aux (rules,res) false "" in
						       match x with
						       | (Some t,s) -> Tree.file_of_dot true (global_options.fileName^".dot") t;
						       | (None,_) -> printf "vdm";
                                  | _ -> printf "Shit happened";
                                  end
  | None -> printf "J'ai rien trouve";
