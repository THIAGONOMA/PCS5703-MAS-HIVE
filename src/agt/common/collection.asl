// ============================================================
// collection.asl — Ciclo de coleta de blocos (visual-first)
// Prioriza percepção visual direta (thing percepts) sobre
// coordenadas SharedMap para navegação confiável em cave maze.
// Incluir ANTES de navigation.asl para prioridade de +step(N)
// ============================================================

// --- Step: resultado do attach veio (prioridade maxima) ---

+step(N)
    : waiting_attach_result(Dir, Type) & lastActionResult(success) & my_pos(MX, MY)
    <- -waiting_attach_result(Dir, Type);
       .abolish(collecting(_, _, _));
       .abolish(has_destination(_, _));
       .abolish(searching_dispenser(_));
       .abolish(collect_nav_start(_));
       +collected_block(Type);
       .print("[COL] Step ", N, ": Bloco ", Type, " attached com sucesso! Pos(", MX, ",", MY, ")");
       action("skip").

+step(N)
    : waiting_attach_result(Dir, Type) & lastActionResult(R) & my_pos(MX, MY)
    <- -waiting_attach_result(Dir, Type);
       .print("[COL] Step ", N, ": Attach falhou: ", R, ". Retentando...");
       .concat("attach(", Dir, ")", Act);
       action(Act);
       +waiting_attach_result(Dir, Type).

// --- Step: request deu certo, agora fazer attach ---

+step(N)
    : waiting_request(Dir, Type) & lastActionResult(success) & my_pos(MX, MY)
    <- -waiting_request(Dir, Type);
       .print("[COL] Step ", N, ": Request OK! Fazendo attach(", Dir, ")");
       .concat("attach(", Dir, ")", Act);
       action(Act);
       +waiting_attach_result(Dir, Type).

// request falhou com failed_target: dispenser não na direção esperada
+step(N)
    : waiting_request(Dir, Type) & lastActionResult(failed_target) & my_pos(MX, MY)
    <- -waiting_request(Dir, Type);
       if (thing(0, -1, dispenser, Type)) { VDir = n }
       elif (thing(0, 1, dispenser, Type)) { VDir = s }
       elif (thing(1, 0, dispenser, Type)) { VDir = e }
       elif (thing(-1, 0, dispenser, Type)) { VDir = w }
       else { VDir = none };
       if (VDir \== none) {
           .print("[COL] Step ", N, ": failed_target, dispenser visivel em ", VDir);
           .concat("request(", VDir, ")", Act);
           action(Act);
           +waiting_request(VDir, Type)
       } else {
           .print("[COL] Step ", N, ": failed_target, dispenser sumiu. Buscando outro.");
           .abolish(collecting(_, _, _));
           .abolish(has_destination(_, _));
           +searching_dispenser(Type);
           !do_explore(MX, MY)
       }.

// request falhou com failed_random: retry
+step(N)
    : waiting_request(Dir, Type) & lastActionResult(failed_random) & my_pos(MX, MY)
    <- .print("[COL] Step ", N, ": Request failed_random. Retentando...");
       .concat("request(", Dir, ")", Act);
       action(Act).

// request falhou genérico: move lateral e retry
+step(N)
    : waiting_request(Dir, Type) & lastActionResult(R) & my_pos(MX, MY)
    <- -waiting_request(Dir, Type);
       if (request_retries(Type, OldR)) {
           -request_retries(Type, OldR); NewR = OldR + 1
       } else {
           NewR = 1
       };
       +request_retries(Type, NewR);
       if (NewR >= 4) {
           -request_retries(Type, _);
           .abolish(collecting(_, _, _));
           .abolish(has_destination(_, _));
           .print("[COL] Step ", N, ": Request falhou ", NewR, "x (", R, "). Explorando.");
           +searching_dispenser(Type);
           !do_explore(MX, MY)
       } else {
           .print("[COL] Step ", N, ": Request falhou: ", R, " (", NewR, "/4).");
           .abolish(last_attempted_dir(_));
           if (Dir == n | Dir == s) {
               .random(RR); if (RR < 0.5) { +last_attempted_dir(e); action("move(e)") } else { +last_attempted_dir(w); action("move(w)") }
           } else {
               .random(RR); if (RR < 0.5) { +last_attempted_dir(n); action("move(n)") } else { +last_attempted_dir(s); action("move(s)") }
           }
       }.

// --- ESCAPE: blocked move durante coleta → escape_move para destravar ---
// Sem este handler, a coleta fica presa tentando a mesma direção bloqueada
// indefinidamente (collection.asl tem prioridade sobre navigation.asl).

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & (last_move_blocked | escape_pending(_, _))
      & thing(VX, VY, dispenser, Type) & (math.abs(VX) + math.abs(VY) > 1)
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       TargX = MX + VX; TargY = MY + VY;
       !escape_move(MX, MY, TargX, TargY).

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & (last_move_blocked | escape_pending(_, _))
      & has_destination(DX, DY)
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       !escape_move(MX, MY, DX, DY).

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & (last_move_blocked | escape_pending(_, _))
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       !do_explore(MX, MY).

// --- ON-DISPENSER: agente em cima do dispenser → move 1 cell para ficar adjacente ---

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption
      & thing(0, 0, dispenser, Type)
    <- .print("[COL] Step ", N, ": Em cima do dispenser ", Type, "! Saindo para ficar adjacente.");
       .abolish(has_destination(_, _));
       +has_destination(MX, MY);
       if (not cell_blocked(0, 1)) { Dir = s }
       elif (not cell_blocked(1, 0)) { Dir = e }
       elif (not cell_blocked(0, -1)) { Dir = n }
       else { Dir = w };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

// --- VISUAL-FIRST: dispenser do tipo certo visivel adjacente → request ---
// Guard: não tentar request se já há bloco attached nessa posição

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption
      & thing(VX, VY, dispenser, Type)
      & (math.abs(VX) + math.abs(VY) == 1)
      & not attached(VX, VY)
    <- if (VY == -1) { Dir = n }
       elif (VY == 1) { Dir = s }
       elif (VX == 1) { Dir = e }
       else { Dir = w };
       .print("[COL] Step ", N, ": Dispenser ", Type, " adjacente visual! request(", Dir, ")");
       .abolish(has_destination(_, _));
       .concat("request(", Dir, ")", Act);
       action(Act);
       +waiting_request(Dir, Type).

// Dispenser adjacente mas bloqueado por bloco attached → circundar
+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption
      & thing(VX, VY, dispenser, Type)
      & (math.abs(VX) + math.abs(VY) == 1)
      & attached(VX, VY)
    <- if (VX == 0) {
           if (not attached(1, 0)) { Dir = e }
           elif (not attached(-1, 0)) { Dir = w }
           else { Dir = e }
       } else {
           if (not attached(0, 1)) { Dir = s }
           elif (not attached(0, -1)) { Dir = n }
           else { Dir = s }
       };
       .print("[COL] Step ", N, ": Dispenser ", Type, " adjacente bloqueado por bloco. Circundando ", Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

// --- VISUAL-FIRST: dispenser visivel proximo → pathfind com fallback greedy ---

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption & not last_move_blocked & not escape_pending(_, _)
      & thing(VX, VY, dispenser, Type)
      & (math.abs(VX) + math.abs(VY) > 1)
    <- TargX = MX + VX; TargY = MY + VY;
       .abolish(has_destination(_, _));
       +has_destination(TargX, TargY);
       compute_next_move(MX, MY, TargX, TargY, Dir);
       if ((N mod 20) == 0) {
           .print("[COL] Step ", N, ": Dispenser ", Type, " em (", VX, ",", VY, ") → ", Dir)
       };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

// --- STUCK: navegando ao dispenser há muitos steps sem chegar → explorar ---
// Ao recalcular, se o dispenser mais próximo é distante (>20 cells), melhor
// explorar e usar visual-first do que insistir em navegação direta pelo maze.

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & has_destination(DX, DY) & collect_nav_start(StartStep)
      & (N - StartStep > 25)
    <- .abolish(collect_nav_start(_));
       +collect_nav_start(N);
       .abolish(has_destination(_, _));
       .abolish(collecting(_, _, _));
       get_nearest_dispenser(MX, MY, Type, NDX, NDY);
       if (NDX \== -1) {
           MDist = math.abs(NDX - MX) + math.abs(NDY - MY);
           if (MDist == 0) {
               .print("[COL] Step ", N, ": Dispenser ", Type, " no mapa em pos atual mas nao visivel. Explorando.");
               +collecting(Type, 0, 0);
               !do_explore(MX, MY)
           } elif (MDist <= 6) {
               .print("[COL] Step ", N, ": Recalc dispenser ", Type, " (", NDX, ",", NDY, ") dist=", MDist);
               +collecting(Type, NDX, NDY);
               +has_destination(NDX, NDY)
           } else {
               .print("[COL] Step ", N, ": Dispenser ", Type, " distante (", NDX, ",", NDY, ") d=", MDist, ". Explorando.");
               +collecting(Type, 0, 0);
               !do_explore(MX, MY)
           }
       } else {
           .print("[COL] Step ", N, ": Stuck, explorando para ", Type);
           +collecting(Type, 0, 0);
           !do_explore(MX, MY)
       }.

// --- FALLBACK: coletando sem dispenser visível → explorar ---
// Consulta SharedMap a cada 10 steps; só navega se próximo (≤15 cells).

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption
      & not has_destination(_, _)
    <- if ((N mod 10) == 0) {
           get_nearest_dispenser(MX, MY, Type, DX, DY);
           if (DX \== -1) {
               MDist = math.abs(DX - MX) + math.abs(DY - MY);
               if (MDist > 0 & MDist <= 6) {
                   .print("[COL] Step ", N, ": Dispenser ", Type, " em (", DX, ",", DY, ") d=", MDist, ". Nav.");
                   .abolish(collecting(_, _, _));
                   +collecting(Type, DX, DY);
                   +has_destination(DX, DY);
                   .abolish(collect_nav_start(_));
                   +collect_nav_start(N)
               }
           }
       };
       !do_explore(MX, MY).

// --- ARRIVED AT DESTINATION: chegou mas dispenser nao visivel → explorar ---

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption
      & has_destination(DX, DY) & DX == MX & DY == MY
      & not thing(0, 0, dispenser, Type)
    <- .print("[COL] Step ", N, ": Chegou em (", DX, ",", DY, ") mas dispenser ", Type, " nao visivel. Explorando.");
       .abolish(has_destination(_, _));
       .abolish(collect_nav_start(_));
       !do_explore(MX, MY).

+step(N)
    : collecting(Type, _, _) & my_pos(MX, MY)
      & not waiting_request(_, _) & not waiting_attach_result(_, _)
      & not need_role_adoption & not last_move_blocked & not escape_pending(_, _)
      & has_destination(DX, DY)
    <- compute_next_move(MX, MY, DX, DY, Dir);
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

// --- Goal: iniciar coleta ---

+!collect_block(Type)
    : my_pos(MX, MY) & not norm_allows_carry
    <- .print("[COL] Norm Carry impede coleta! Aguardando norma expirar.").

+!collect_block(Type)
    : my_pos(MX, MY) & attached(_, _) & not solo_block_type(_)
    <- .print("[COL] Stale blocks detected, clearing before collection");
       +needs_clear_blocks(Type).

+!collect_block(Type)
    : my_pos(MX, MY) & step(CS)
    <- .print("[COL] Iniciando coleta de ", Type, ". pos=(", MX, ",", MY, ")");
       .abolish(searching_dispenser(_));
       .abolish(collecting(_, _, _));
       .abolish(has_destination(_, _));
       .abolish(collect_nav_start(_));
       +collect_nav_start(CS);
       get_nearest_dispenser(MX, MY, Type, DX, DY);
       if (DX \== -1) {
           MDist = math.abs(DX - MX) + math.abs(DY - MY);
           if (MDist == 0) {
               .print("[COL] Dispenser ", Type, " no mapa em pos atual. Explorando para adjacente.");
               +collecting(Type, 0, 0);
               !do_explore(MX, MY)
           } elif (MDist <= 6) {
               .print("[COL] Dispenser ", Type, " em (", DX, ",", DY, ") d=", MDist, ". Nav.");
               +collecting(Type, DX, DY);
               +has_destination(DX, DY)
           } else {
               .print("[COL] Dispenser ", Type, " distante (", DX, ",", DY, ") d=", MDist, ". Explorando.");
               +collecting(Type, 0, 0);
               !do_explore(MX, MY)
           }
       } else {
           .print("[COL] Nenhum dispenser ", Type, " conhecido. Explorando.");
           +collecting(Type, 0, 0);
           !do_explore(MX, MY)
       }.

+!collect_block(_) <- true.

// --- Retry dispenser search periodically while exploring ---

+step(N)
    : searching_dispenser(Type) & my_pos(MX, MY) & (N mod 20) == 0
      & not collecting(_, _, _) & not waiting_request(_, _) & not waiting_attach_result(_, _)
    <- .print("[COL] Step ", N, ": searching_dispenser(", Type, ") explorando...").

// --- Detach e Rotate ---

+!detach_block(Dir)
    <- .concat("detach(", Dir, ")", Act); action(Act).

+!rotate(Dir)
    <- .concat("rotate(", Dir, ")", Act); action(Act).
