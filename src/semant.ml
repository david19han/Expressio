(* Semantic checking for the MicroC compiler *)

open Ast
open Sast
open Prelude

module StringMap = Map.Make(String)
(* Semantic checking of the AST. Returns an SAST if successful,
   throws an exception if something is wrong.

   Check each global variable, then check each function *)

(* let check (globals, dfas, functions) = *)
  let check (globals, _, functions) =

  (* Check if a certain kind of binding has void type or is a duplicate
     of another, previously checked binding *)
  let check_binds (kind : string) (to_check : bind list) =
    let check_it checked binding =
      let void_err = "illegal void " ^ kind ^ " " ^ snd binding
      and dup_err = "duplicate " ^ kind ^ " " ^ snd binding
      in match binding with
        (* No void bindings *)
        (TUnit, _) -> raise (Failure void_err)
      | (_, n1) -> match checked with
                    (* No duplicate bindings *)
                      ((_, n2) :: _) when n1 = n2 -> raise (Failure dup_err)
                    | _ -> binding :: checked
    in let _ = List.fold_left check_it [] (List.sort compare to_check)
       in to_check

  (**** Checking Global Variables ****)

  in let globals' = check_binds "global" globals
  in let dfas' : sdfa_decl list = [] (* check_binds "dfa" dfas *)
  (**** Checking Functions ****)

  (* Collect function declarations for built-in functions: no bodies *)
  in let built_in_decls =
    let add_bind map (name, ty) = StringMap.add name { typ     = TUnit
                                                     ; fname   = name
                                                     ; formals = [(ty, "x")]
                                                     ; locals  = []
                                                     ; body    = []
                                                     } map
    in List.fold_left add_bind StringMap.empty [ ("print", TInt); ("printb", TBool); ("printbig", TInt)]
(*
                                                    { typ     = TUnit
                                                    ; fname   = "print"
                                                    ; formals = [(TInt, "x")]
                                                    ; locals  = []
                                                    ; body    = []
                                                    } map
                                                    *)

  (* Add function name to symbol table *)
  in let add_func map fd =
    let built_in_err = "function " ^ fd.fname ^ " may not be defined"
    and dup_err      = "duplicate function " ^ fd.fname
    and make_err er = raise (Failure er)
    and n = fd.fname (* Name of the function *)
    in match fd with (* No duplicate functions or redefinitions of built-ins *)
         _ when StringMap.mem n built_in_decls -> make_err built_in_err
       | _ when StringMap.mem n map -> make_err dup_err
       | _ ->  StringMap.add n fd map

  (* Collect all other function names into one symbol table *)
  in let function_decls = List.fold_left add_func built_in_decls functions

  (* Return a function from our symbol table *)
  in let find_func s =
    try StringMap.find s function_decls
    with Not_found -> raise (Failure ("unrecognized function " ^ s))


  in let _ = find_func "main" (* Ensure "main" is defined *)

  in let check_function func =
    (* Make sure no formals or locals are void or duplicates *)
    let formals'   = check_binds "formal" func.formals
    in let locals' = check_binds "local"  func.locals
    (* Raise an exception if the given rvalue type cannot be assigned to
       the given lvalue type *)
    in let check_assign lvaluet rvaluet err = if lvaluet = rvaluet
                                              then lvaluet
                                              else raise (Failure err)
    (* Build local symbol table of variables for this function *)
    in let bindings : bind list = (globals' @ formals' @ locals')
    in let symbols = Prelude.fromList (List.map Prelude.swap bindings)

    (* Return a variable from our local symbol table *)
    (* TODO write a generic map lookup method instead of this silly exception *)
    in let type_of_identifier s =
      try StringMap.find s symbols
      with Not_found -> raise (Failure ("undeclared identifier " ^ s))


    (* Return a semantically-checked expression, i.e., with a type *)
    in let rec expr ex = match ex with
        IntLit  l             -> (TInt, SIntLit l)
      | CharLit c             -> (TChar, SCharLit c)
      | StringLit s           -> (TString, SStringLit s)
      | BoolLit l             -> (TBool, SBoolLit l)
      | DFA (states, alpha, start, final, tran)   ->
                                 (* check states is greater than final states *)
                                 let rec checkFinal maxVal = function
                                 [] -> false
                                 | x :: tl -> if maxVal <= x then true else checkFinal maxVal tl in

                                 (* check states is greater than start/final in transition *)
                                 let rec checkTran maxVal = function
                                 [] -> false
                                 | x :: tl -> let (t1,t2,t3) = x in if maxVal <= t1 || maxVal <= t3 then true else checkTran maxVal tl in

                                 (* check transition table has one to one *)
                                 let rec oneToOne sMap = function
                                 [] -> false
                                 | x :: tl -> let (t1,t2,t3) = x in
                                   let combo = string_of_int t1 ^ String.make 1 t2 in
                                   let finalState = string_of_int t3 in
                                   if StringMap.mem combo sMap then true else oneToOne (StringMap.add combo finalState sMap) tl in

                                 (* also check that states is greater than start *)
                                 if states <= start ||  checkFinal states final || checkTran states tran || oneToOne StringMap.empty tran
                                 then raise (Failure ("DFA sucks"))
                                 else (TDFA, SDFA (states,alpha,start,final,tran))
      | RE r                  -> (* let check = raise (Prelude.TODO "implement any needed checking here")
                                 in*) (TRE, SRE r)
      | Noexpr                -> (TUnit, SNoexpr)
      | Id s                  -> (type_of_identifier s, SId s)
      | Assign (var, e) as ex -> let lt = type_of_identifier var
                                 and (rt, e') = expr e
                                 in let err = "illegal assignment " ^ string_of_typ lt ^ " = " ^ string_of_typ rt ^ " in " ^ string_of_expr ex
                                 in (check_assign lt rt err, SAssign (var, (rt, e')))
      | UnopPost (e, op)      -> expr (UnopPre (op, e))
      | UnopPre (op, e) as ex ->
          let (t, e') = expr e
          in let ty = match op with
                        UNeg when t = TInt  -> t
                      | UNot when t = TBool -> TBool
                      | _ -> raise (Failure ("illegal unary operator " ^
                                             string_of_uop op ^ string_of_typ t ^
                                             " in " ^ string_of_expr ex))
          in (ty, SUnopPre (op, (t, e')))
      | Binop (e1, op, e2) as e ->
          let (t1, e1') = expr e1
          and (t2, e2') = expr e2
          (* All binary operators require operands of the same type *)
          in let same = t1 = t2
          (* Determine expression type based on operator and operand types *)
          in let ty = match op with
                          BAdd
                        | BSub
                        | BMult
                        | BDiv     when same && t1 = TInt  -> TInt
                        | BEqual
                        | BNeq     when same               -> TBool
                        | BLess
                        | BLeq
                        | BGreater
                        | BGeq     when same && t1 = TInt  -> TBool
                        | BAnd
                        | BOr      when same && t1 = TBool -> TBool
                        | _ -> raise (Failure ("illegal binary operator " ^
                                               string_of_typ t1 ^ " " ^ string_of_op op ^ " " ^
                                               string_of_typ t2 ^ " in " ^ string_of_expr e))
        in (ty, SBinop ((t1, e1'), op, (t2, e2')))
      | Call (fname, args) as call ->
          let fd           = find_func fname
          in let param_length = List.length fd.formals
          in if List.length args != param_length
             then raise (Failure ("expecting " ^ string_of_int param_length ^ " arguments in " ^ string_of_expr call))
             else let check_call (ft, _) e = let (et, e') = expr e
                                             in let err = "illegal argument found " ^ string_of_typ et ^ " expected " ^ string_of_typ ft ^ " in " ^ string_of_expr e
                  in (check_assign ft et err, e')
          in let args' = List.map2 check_call fd.formals args
          in (fd.typ, SCall (fname, args'))
    in let check_bool_expr e = let (t', e') = expr e
                               and err = "expected Boolean expression in " ^ string_of_expr e
                               in if t' != TBool
                                  then raise (Failure err)
                                  else (t', e')


    (* Return a semantically-checked statement i.e. containing sexprs *)
    (* in let rec check_stmt (x : stmt) : sstmt = match x with *)
    (* check_stmt : stmt -> sstmt *)
    in let rec check_stmt = function
        Expr e               -> SExpr (expr e)
      | If (p, b1, b2)       -> SIf (check_bool_expr p, check_stmt b1, check_stmt b2)
      | For (e1, e2, e3, st) -> SFor (expr e1, check_bool_expr e2, expr e3, check_stmt st)
      | While (p, s)         -> SWhile (check_bool_expr p, check_stmt s)
      | Infloop (s)          -> SInfloop (check_stmt s)
      | Continue             -> raise (Prelude.TODO "semant check_stmt Continue")
      | Break                -> raise (Prelude.TODO "semant check_stmt Break")
      | Return e             -> let (t, e') = expr e
                                in if t = func.typ
                                   then SReturn (t, e')
                                   else raise (Failure ("return gives " ^ string_of_typ t ^ " expected " ^ string_of_typ func.typ ^ " in " ^ string_of_expr e))
	    (* A block is correct if each statement is correct and nothing
	       follows any Return statement.  Nested blocks are flattened. *)
      | Block sl ->
          let rec check_stmt_list = function
              [Return _ as s] -> [check_stmt s]
            | Return _ :: _   -> raise (Failure "nothing may follow a return")
            | Block sl :: ss  -> check_stmt_list (sl @ ss) (* Flatten blocks *)
            | s :: ss         -> check_stmt s :: check_stmt_list ss
            | []              -> []
          in SBlock (check_stmt_list sl)

    in (* body of check_function *)
    { styp     = func.typ;
      sfname   = func.fname;
      sformals = formals';
      slocals  = locals';
      sbody    = match check_stmt (Block func.body) with
                	 SBlock sl -> sl
                  | _        -> let err = "internal error: block didn't become a block?"
                                in raise (Failure err)
    }
  in (globals', dfas',List.map check_function functions)
