(*  Ian Treyball      <ict2102@columbia.edu>
 Lalka Rieger      <ler2161@columbia.edu>
 Chengtian Xu      <cx2168@columbia.edu>
 David Han         <dth2126@columbia.edu> *)

(* Semantic checking for the MicroC compiler *)

open Ast
open Sast
open Prelude.Prelude
(* open RegExp *)

(* module StringMap = Map.Make(String) *)
(* Semantic checking of the AST. Returns an SAST if successful,
   throws an exception if something is wrong.

   Check each global variable, then check each function *)

(* let check (globals, dfas, functions) = *)
  let check ((globals, _, functions) : program) : sprogram =

  (* Check if a certain kind of binding has void type or is a duplicate
     of another, previously checked binding *)
  let check_binds (kind : string) (to_check : bind list) : bind list =
    let check_it (checked : bind list) (binding : bind) =
      match binding with
        (* No void bindings *)
        (TUnit,  _) -> error ("illegal void " ^ kind ^ " " ^ snd binding)
      | (_,     n1) -> match checked with
                        (* No duplicate bindings *)
                        ((_, n2) :: _) when n1 = n2 -> error ("duplicate " ^ kind ^ " " ^ snd binding)
                       | _                          -> binding :: checked
    in let _ = List.fold_left check_it [] (List.sort compare to_check)
       in to_check

  (**** Checking Global Variables ****)

  in let globals' : bind list = check_binds "global" globals
  in let dfas' : sdfa_decl list = [] (* check_binds "dfa" dfas *)
  (**** Checking Functions ****)

  (* Collect function declarations for built-in functions: no bodies *)
  and built_in_decls : func_decl string_map =
    let add_bind ((rt, ty, name)) : (string * func_decl) = (name, { typ     = rt
                                                                  ; fname   = name
                                                                  ; formals = [(ty, "x")]
                                                                  ; locals  = []
                                                                  ; body    = []
                                                                  })
    (* manually define the `matches` function because it is not as basic as the rest of the built-in functions *)
    and matches_fn : (string * func_decl) = ("matches", { typ      = TBool
                                                        ; fname   = "matches"
                                                        ; formals = [(TString, "x") ; (TRE, "y")]
                                                        ; locals  = []
                                                        ; body    = []
                                                        })
    in let built_ins : (string * func_decl) list = matches_fn :: (List.map add_bind [ (TUnit, TInt,    "print")
                                                                                    ; (TUnit, TRE,     "printr")
                                                                                    ; (TUnit, TDFA,    "printdfa")
                                                                                    ; (TUnit, TString, "printf")
                                                                                    ; (TUnit, TBool,   "printb")
                                                                                    ; (TChar, TRE,     "litchar")
                                                                                    ; (TChar, TRE,     "outer")
                                                                                    ; (TRE,   TRE,     "righttok")
                                                                                    ; (TRE,   TRE,     "lefttok")
                                                                                    ; (TUnit, TChar,   "printc")
                                                                                    ; (TInt,  TString, "len")
                                                                                    ])
    in let built_ins : (string * func_decl) list = ("matches", { typ = TBool
                                                               ; fname = "matches"
                                                               ; formals = [(TString, "x") ; (TRE, "y")]
                                                               ; locals = []
                                                               ; body = []
                                                               }) :: built_ins
    in let built_ins : (string * func_decl) list = ("link", { typ = TInt
                                                            ; fname = "link"
                                                            ; formals = [(TDFA, "x") ; (TInt, "y"); (TChar, "z"); (TInt, "w")]
                                                            ; locals = []
                                                            ; body = []
                                                            }) :: built_ins
    in let built_ins : (string * func_decl) list = ("randomr", { typ = TInt
                                                            ; fname = "randomr"
                                                            ; formals = [(TInt, "y")]
                                                            ; locals = []
                                                            ; body = []
                                                            }) :: built_ins
    in fromList (built_ins)


  (* Add function name to symbol table *)
  in let add_func map fd = if      StringMap.mem fd.fname built_in_decls
                           then      error ("function "           ^ fd.fname ^ " may not be defined")
                           else if StringMap.mem fd.fname map
                                then error ("duplicate function " ^ fd.fname)
                                else StringMap.add fd.fname fd map

  (* Collect all other function names into one symbol table *)
  in let function_decls : func_decl string_map = List.fold_left add_func built_in_decls functions

  (* Return a function from our symbol table *)
  in let find_func s = match StringMap.find_opt s function_decls with
        Some s' -> s'
      | None    -> error ("unrecognized function " ^ s)


  in let _ = find_func "main" (* Ensure "main" is defined *)

  and check_function (func : func_decl) : sfunc_decl =
    (* Make sure no formals or locals are void or duplicates *)
    let formals' : bind list = check_binds "formal" func.formals
    and locals'  : bind list = check_binds "local"  func.locals
    (* Raise an exception if the given rvalue type cannot be assigned to
       the given lvalue type *)
    and check_assign (lvaluet : typ) (rvaluet : typ) err = if lvaluet = rvaluet
                                              then lvaluet
                                              else error err
    (* Build local symbol table of variables for this function *)
    in let bindings : bind list = (globals' @ formals' @ locals')
    in let symbols : Ast.typ string_map = fromList (List.map swap bindings)

    (* Return a variable from our local symbol table *)
    in let type_of_identifier (s : string) : typ = match StringMap.find_opt s symbols with
        Some s' -> s'
      | None    -> error ("undeclared identifier " ^ s)

    in let rec type_of_expr e = fst (expr e)

    (* Return a semantically-checked expression, i.e., with a type *)
    (* in let rec expr = function *)
    and expr (ex : expr) : sexpr = match ex with
        IntLit  l                                 -> (TInt,    SIntLit l)
      | CharLit c                                 -> (TChar,   SCharLit c)
      | StringLit s                               -> (TString, SStringLit s)
      | BoolLit l                                 -> (TBool,   SBoolLit l)
      (* TODO clean this up a bit *)
      | DFA (states1, alpha, start1, final, tran) when fst (expr states1) = TInt
                                                    && fst (expr start1)  = TInt ->
                                 let states = match expr states1 with
                                              (TInt,  sint) -> snd (eval_sint StringMap.empty sint)
                                             | _            -> error ("internal error: DFA field failed to evaluate " ^ string_of_sexpr (expr states1))
                                 and start = match expr start1 with
                                              (TInt,  sint) -> snd (eval_sint StringMap.empty sint)
                                             | _            -> error ("internal error: DFA field failed to evaluate " ^ string_of_sexpr (expr start1))
                                 (* ensure all states used in the DFA definition are in bounds *)
                                 in let in_bounds q = q <= states
                                 in let rec checkFinal = List.for_all                    in_bounds final
                                    and     checkStart =                                 in_bounds start
                                    and     checkTran  = List.for_all (fun (q, _, p) -> (in_bounds q
                                                                                      && in_bounds p)) tran
                                    (* check transition table is actually a function (one to one mapping) *)
                                    and     oneToOne map = function
                                      []                 -> false
                                    | (t1, t2, t3) :: tl -> let combo      = string_of_int t1 ^ String.make 1 t2
                                                            and finalState = string_of_int t3
                                                            in if StringMap.mem combo map then true else oneToOne (StringMap.add combo finalState map) tl
                                 in if checkStart &&  checkFinal && checkTran && oneToOne StringMap.empty tran
                                    then error "DFA invalid"
                                    else (TDFA, SDFA (states, alpha, start, final, tran))
      | DFA (_, _, _, _, _)   -> error "The expression for the given DFA's states/start was not an int"
      | RE r                  -> (* let check = raise (Prelude.TODO "implement any needed checking here")
                                 in*) (TRE, SRE r)
      | Noexpr                -> (TUnit, SNoexpr)
      | Id s                  -> (type_of_identifier s, SId s)
      | Assign (var, e) as ex -> let lt = type_of_identifier var
                                 and (rt, e') = expr e
                                 in let err = "illegal assignment " ^ string_of_typ lt ^ " = " ^ string_of_typ rt ^ " in " ^ string_of_expr ex
                                 in (check_assign lt rt err, SAssign (var, (rt, e')))
      | Unop (UNeg,    e) when fst (expr e) = TInt  -> (TInt,  SUnop (UNeg, expr e))
      | Unop (UNeg,    e) as ex                     -> error ("illegal unary operator " ^ string_of_uop UNeg    ^ string_of_typ (fst (expr e)) ^ " in " ^ string_of_expr ex)
      | Unop (UNot,    e) when fst (expr e) = TBool -> (TBool, SUnop (UNot,    expr e))
      | Unop (UNot,    e) as ex                     -> error ("illegal unary operator " ^ string_of_uop UNot    ^ string_of_typ (fst (expr e)) ^ " in " ^ string_of_expr ex)
      | Unop (URELit,  e) when fst (expr e) = TChar -> (TRE,   SUnop (URELit,  expr e))
      | Unop (URELit,  e) as ex                     -> error ("illegal unary operator " ^ string_of_uop URELit  ^ string_of_typ (fst (expr e)) ^ " in " ^ string_of_expr ex)
      | Unop (UREStar, e) when fst (expr e) = TRE   -> (TRE,   SUnop (UREStar, expr e))
      | Unop (UREStar, e) as ex                     -> error ("illegal unary operator " ^ string_of_uop UREStar ^ string_of_typ (fst (expr e)) ^ " in " ^ string_of_expr ex)
      | Unop (UREComp, e) when fst (expr e) = TRE   -> (TRE,   SUnop (UREComp, expr e))
      | Unop (UREComp, e) as ex                     -> error ("illegal unary operator " ^ string_of_uop UREComp ^ string_of_typ (fst (expr e)) ^ " in " ^ string_of_expr ex)
      (* | Unop (UREOut,  e) when fst (expr e) = TRE   -> (TRE,   SUnop (UREComp, expr e)) *)
      (* | Unop (UREOut,  e) as ex                     -> error ("illegal unary operator " ^ string_of_uop UREOut  ^ string_of_typ (fst (expr e)) ^ " in " ^ string_of_expr ex) *)
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
                        | BDiv          when same      && t1 = TInt    -> TInt
                        | BEqual
                        | BNeq          when same                      -> TBool
                        | BLess
                        | BLeq
                        | BGreater
                        | BGeq          when same      && t1 = TInt    -> TBool
                        | BAnd
                        | BOr           when same      && t1 = TBool   -> TBool
                        (* | BREEqual      when same      && t1 = TRE     -> TBool *)
                        | BREUnion
                        | BREConcat
                        | BREIntersect  when same      && t1 = TRE     -> TRE
                        | BREMatches    when t1 = TRE  && t2 = TString -> TBool
                        | BDFAAccepts   when t1 = TDFA && t2 = TString -> TBool
                        | BDFASimulates when t1 = TDFA && t2 = TString -> TInt
                        | BDFAUnion     when t1 = TDFA && t2 = TDFA    -> TDFA
                        | BDFAConcat    when t1 = TDFA && t2 = TDFA    -> TDFA
                        | _ -> error ("illegal binary operator " ^
                                      string_of_typ t1 ^ " " ^ string_of_op op ^ " " ^
                                      string_of_typ t2 ^ " in " ^ string_of_expr e)
        in (ty, SBinop ((t1, e1'), op, (t2, e2')))
      | Ternary(s,e1,e2,op) ->
          let (t1, e1') = expr e1
          and (t2, e2') = expr e2
          (* and (t3, e3') = expr e3 *)
          in (TInt,STernary (s,(t1, e1'), (t2, e2'),op))
      | StringIndex(a,b) ->
                                 let (rt, e') = expr b
                                 in let err = "bad string index"
                               in let _ = check_assign TInt rt err
                                 in (TChar, SStringIndex (a, (rt, e')))
(*       | StringAppend(a,b) -> let (rt, e') = expr b
                                 in let err = "bad string index"
                               in let _ = check_assign TString rt err
                                 in (TString, SStringAppend (a, (rt, e'))) *)
      | Call (fname, args) as call ->
          let fd              = find_func fname
          in let param_length = List.length fd.formals
          in if List.length args != param_length
             then error ("expecting " ^ string_of_int param_length ^ " arguments in " ^ string_of_expr call)
             else let check_call (ft, _) e = let (et, e') = expr e
                                             in let err = "illegal argument found " ^ string_of_typ et ^ " expected " ^ string_of_typ ft ^ " in " ^ string_of_expr e
                  in (check_assign ft et err, e')
          in let args' = List.map2 check_call fd.formals args
          in (fd.typ, SCall (fname, args'))

    in let check_bool_expr e = match (expr e) with
                                (TBool, e') -> (TBool, e')
                              | _           -> error ("expected Boolean expression in " ^ string_of_expr e)

    (* Return a semantically-checked statement i.e. containing sexprs *)
    (* this function was originally a simple `stmt -> sstmt` but with adding continue/break statements it is
       not possible to take any arbitrary `stmt` without more context to determine if said statement is semantically correct,
       so here we pass along some context/state, namely a boolean value which is true if we're in a loop
       false otherwise. *)
    in let rec check_statement (x : (bool * stmt)) : (bool * sstmt) = match x with
      | (false,   Break)                                                 -> error "\'break\' is outside of loop"
      | (false,   Continue)                                              -> error "\'continue\' is outside of loop"
      | (true,    Break)                                                 -> (true,    SBreak)
      | (true,    Continue)                                              -> (true,    SContinue)
      | (looping, (Case (e, ([ ((Noexpr, Noexpr), e1)
                             ; ((Noexpr, Noexpr), e2)
                             ; ((Noexpr, Id s1),  e3)
                             ; ((Id s2,  Id s3),  e4)
                             ; ((Id s4,  Id s5),  e5)
                             ; ((Id s6,  Id s7),  e6)
                             ; ((Noexpr, Id s8),  e7)
                             ; ((Noexpr, Id s9),  e8)
                             ] as cases)))) when fst (expr e) = TRE      -> let rhs = List.map snd cases
                                                                            and check_expressions_have_type (t : typ) = List.for_all (fun a -> type_of_expr a = t)
                                                                            (* ensure that the all the types on the RHS of the case are the same *)
                                                                            in let same_rhs = function
                                                                                     []        -> true
                                                                                   | (e :: es) -> check_expressions_have_type (type_of_expr e) es
                                                                            in (if not (same_rhs rhs)
                                                                                then error "all of RHS must have same type"
                                                                                else (* let outer  : expr = Call ("outer", [e]) *)
                                                                                     let then8 : stmt = Block [ Expr (Assign (s9, (Call ("lefttok",  [e]))))
                                                                                                              ; Expr e8
                                                                                                              ]
                                                                                     and then7 : stmt = Block [ Expr (Assign (s8, (Call ("lefttok",  [e]))))
                                                                                                              ; Expr e7
                                                                                                              ]
                                                                                     and then6 : stmt = Block [ Expr (Assign (s6, (Call ("lefttok",  [e]))))
                                                                                                              ; Expr (Assign (s7, (Call ("righttok", [e]))))
                                                                                                              ; Expr e6
                                                                                                              ]
                                                                                     and then5 : stmt = Block [ Expr (Assign (s4, (Call ("lefttok",  [e]))))
                                                                                                              ; Expr (Assign (s5, (Call ("righttok", [e]))))
                                                                                                              ; Expr e5
                                                                                                              ]
                                                                                     and then4 : stmt = Block [ Expr (Assign (s2, (Call ("lefttok",  [e]))))
                                                                                                              ; Expr (Assign (s3, (Call ("righttok", [e]))))
                                                                                                              ; Expr e4
                                                                                                              ]
                                                                                     and then3 : stmt = Block (List.map (fun e -> Expr e) [Assign (s1, (Call ("litchar",  [e]))); e3])
                                                                                     (* in let if8 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '*'),  then8,   let _ = (error "umm... outer=" ^ (string_of_expr outer)) in Expr (raise ABSURD)) (* this `else` is unreachable if semantic checking worked *) *)
                                                                                     in let if8 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '*'),  then8,   (Expr Noexpr)) (* this `else` is unreachable if semantic checking worked *)
                                                                                     in let if7 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '\''), then7,   if8)
                                                                                     in let if6 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '^'),  then6,   if7)
                                                                                     in let if5 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '|'),  then5,   if6)
                                                                                     in let if4 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '&'),  then4,   if5)
                                                                                     in let if3 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit 'l'),  then3,   if4)
                                                                                     in let if2 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '@'),  Expr e2, if3)
                                                                                     in let if1 : stmt = If (Binop (Call ("outer", [e]), BEqual, CharLit '#'),  Expr e1, if2)
                                                                                     in check_statement (looping, if1))
      | (_,       Case (_, _))                                           -> error "case expressions currently only support regular expressions"
      | (looping, Expr e)                                                -> (looping, SExpr (expr e))
      | (looping, If (p, b1, b2))                                        -> (looping, SIf (check_bool_expr p, snd (check_statement (looping, b1)), snd (check_statement (looping, b2))))
      | (looping, For (e1, e2, e3, s))                                   -> (looping, SFor     (expr e1, check_bool_expr e2, expr e3, snd (check_statement (true, s))))
      | (looping, While (p, s))                                          -> (looping, SWhile   (SNostmt, check_bool_expr p,           snd (check_statement (true, s))))
      | (_,       Infloop s)                                             -> (true,    SInfloop (                                      snd (check_statement (true, s))))
      | (looping, Return e)               when (fst (expr e) = func.typ) -> (looping, SReturn (expr e))
      | (_,       Return e)                                              -> error ("return gives " ^ string_of_typ (fst (expr e)) ^ " expected " ^ string_of_typ func.typ ^ " in " ^ string_of_expr e)
      | (looping, Block (Return e :: [])) when (fst (expr e) = func.typ) -> (looping, SBlock [SReturn (expr e)])
      | (_,       Block (Return e :: []))                                -> error ("return gives " ^ string_of_typ (fst (expr e)) ^ " expected " ^ string_of_typ func.typ ^ " in " ^ string_of_expr e)
      | (_,       Block (Return _ ::  _))                                -> error "nothing may follow a return"
      | (looping, Block (Block sl :: ss))                                -> (looping, snd (check_statement (looping, (Block (sl @ ss)))))           (* Flatten blocks *)
      | (looping, Block              [])                                 -> (looping, SBlock [])
      | (looping, Block              ss)                                 -> let ss' : sstmt list = snd (map_accum_left (curry check_statement) looping ss)
                                                                            in  (looping, SBlock (ss'))
    in (* body of check_function *)
    { styp     = func.typ;
      sfname   = func.fname;
      sformals = formals';
      slocals  = locals';
      sbody    = match (snd (check_statement (false, (Block func.body)))) with (* if we ever decide to support nested functions we should update check_function to pass a boolean variable to indicate the state of looping and include it here instead of `false` *)
                	 SBlock sl -> sl
                  | _        -> error "internal error: block didn't become a block?"
    }
  in (globals', dfas', List.map check_function functions)
