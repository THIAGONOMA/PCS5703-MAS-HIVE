// ============================================================
// navigation.asl — Navegacao step-by-step
// Chamado quando connect_protocol e collection nao interceptam o step
// ============================================================

// --- Collector: chegou ao meeting point → sinalizar pronto ---

+step(N)
    : has_destination(DX, DY) & my_pos(MX, MY) & DX == MX & DY == MY
      & navigating_to_meeting_point(SquadId)
    <- -has_destination(DX, DY);
       -navigating_to_meeting_point(SquadId);
       .my_name(Me);
       signal_ready(SquadId, Me);
       .concat("{\"squad\":\"", SquadId, "\"}", AMJson);
       !dash_log("arrived_meeting", AMJson);
       .print("[NAV] Step ", N, ": Cheguei ao meeting point! Sinalizando pronto.");
       action("skip").

// --- Assembler: chegou ao meeting point para connect ---

+step(N)
    : has_destination(DX, DY) & my_pos(MX, MY) & DX == MX & DY == MY
      & navigating_to_meeting_for_connect(SquadId, _, TaskName)
    <- -has_destination(DX, DY);
       .print("[NAV] Step ", N, ": Assembler no meeting point para task ", TaskName);
       action("skip").

// --- Destino generico alcancado ---

+step(N)
    : has_destination(DX, DY) & my_pos(MX, MY) & DX == MX & DY == MY
    <- -has_destination(DX, DY);
       .print("[NAV] Step ", N, ": Cheguei ao destino (", DX, ",", DY, "). Explorando...");
       .concat("{\"x\":", DX, ",\"y\":", DY, "}", DJ);
       !dash_log("arrived_dest", DJ);
       !do_explore(MX, MY).

// --- Detach forçado quando stuck por 10+ steps ---

+step(N)
    : need_detach(DDir) & solo_mode(TaskName) & pending_submit(TaskName) & my_pos(MX, MY)
    <- -need_detach(DDir);
       .print("[NAV] Step ", N, ": STUCK com bloco para submit! Tentando goal zone alternativa");
       get_alternative_goal_zone(MX, MY, MX, MY, AGX, AGY);
       if (AGX \== -1) {
           .abolish(has_destination(_, _));
           +has_destination(AGX, AGY);
           .print("[NAV] Rota alternativa para (", AGX, ",", AGY, ")")
       } else {
           get_nearest_goal_zone(MX, MY, GX, GY);
           if (GX \== -1) {
               .abolish(has_destination(_, _));
               +has_destination(GX, GY)
           }
       };
       .random(R);
       if (R < 0.25) { Dir = n }
       elif (R < 0.5) { Dir = e }
       elif (R < 0.75) { Dir = s }
       else { Dir = w };
       .concat("move(", Dir, ")", Act);
       action(Act).

+step(N)
    : need_detach(DDir) & solo_mode(TaskName)
    <- -need_detach(DDir);
       .print("[NAV] Step ", N, ": STUCK durante coleta solo. Detach(", DDir, ")");
       if (attached(_, _)) { .print("[DETACH] carrier step ", N) };
       .concat("detach(", DDir, ")", Act);
       action(Act).

+step(N)
    : need_detach(DDir)
    <- -need_detach(DDir);
       .print("[NAV] Step ", N, ": STUCK! Detach(", DDir, ") para destravar");
       if (attached(_, _)) { .print("[DETACH] carrier step ", N) };
       .concat("detach(", DDir, ")", Act);
       action(Act).

// --- Desvio de obstaculo: direcao aleatoria (4 direcoes iguais) ---

+step(N)
    : has_destination(DX, DY) & my_pos(MX, MY) & (last_move_blocked | escape_pending(_, _))
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       !escape_move(MX, MY, DX, DY).

// --- Navegar ao destino (greedy inline) ---

+step(N)
    : has_destination(DX, DY) & my_pos(MX, MY) & pending_submit(TN)
    <- compute_next_move(MX, MY, DX, DY, Dir);
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act);
       if ((N mod 20) == 0) {
           .print("[NAV] Step ", N, ": nav to goal zone (", DX, ",", DY, ") for submit ", TN, " from (", MX, ",", MY, ")")
       }.

+step(N)
    : has_destination(DX, DY) & my_pos(MX, MY)
    <- compute_next_move(MX, MY, DX, DY, Dir);
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

// --- Exploracao (sem destino) ---

+step(N)
    : my_pos(MX, MY) & not my_active_task(_, _)
    <- if ((N mod 40) == 0) {
           get_map_stats(V, D, G, R);
           .print("[NAV] Step ", N, " Pos(", MX, ",", MY, ") Map: vis=", V, " disp=", D, " goal=", G, " role=", R)
       };
       !do_explore(MX, MY).

+step(N)
    : my_pos(MX, MY) & my_active_task(TN, _) & (N mod 20) == 0
    <- .print("[NAV] Step ", N, ": task=", TN, " ativa sem handler especifico! exploring. pos=(", MX, ",", MY, ")");
       get_map_stats(V, D, G, R);
       .print("[NAV]   map: vis=", V, " disp=", D, " goal=", G, " role=", R);
       if (collecting(CT, CDX, CDY)) { .print("[NAV]   collecting(", CT, ",", CDX, ",", CDY, ")") };
       if (pending_submit(PS)) { .print("[NAV]   pending_submit(", PS, ")") };
       if (searching_dispenser(SD)) { .print("[NAV]   searching_dispenser(", SD, ")") };
       !do_explore(MX, MY).

+step(N)
    : my_pos(MX, MY)
    <- !do_explore(MX, MY).

+step(N)
    <- .print("[NAV] Step ", N, ": Sem posicao, skip");
       action("skip").

// --- Exploração: corridor-following biased (#49) ---
// Em cave maze 0.6, A* para fronteiras distantes falha porque mapa é
// desconhecido. Estratégia: mover na direção preferida (setor), e quando
// bloqueado, seguir corredores usando percepção visual direta.
// Rotação do setor a cada 60 steps amplia cobertura.

+!do_explore(MX, MY)
    : not sector_dir(_, _)
    <- .my_name(Me);
       get_sector_target(Me, 20, SX, SY);
       +sector_dir(SX, SY);
       +sector_epoch(0);
       !do_corridor_explore(MX, MY).

+!do_explore(MX, MY)
    : sector_dir(OX, OY) & step(N) & sector_epoch(E) & (N - E > 60)
    <- -sector_epoch(_); +sector_epoch(N);
       .abolish(sector_dir(_, _));
       NX = 0 - OY; NY = OX;
       +sector_dir(NX, NY);
       !do_corridor_explore(MX, MY).

+!do_explore(MX, MY)
    <- !do_corridor_explore(MX, MY).

-!do_explore(_, _)
    <- .abolish(last_attempted_dir(_));
       +last_attempted_dir(n);
       action("move(n)").

// Corridor-following: tenta mover na dir preferida do setor; se bloqueado
// (obstáculo visível), roda para perpendicular disponível. Nunca usa A*
// para alvos distantes desconhecidos — apenas percepção local.
+!do_corridor_explore(MX, MY)
    : sector_dir(SX, SY)
    <- // Calcula direção cardeal preferida a partir do vetor setor
       if (math.abs(SX) >= math.abs(SY)) {
           if (SX > 0) { PrefDir = e; AltDir1 = n; AltDir2 = s; BackDir = w }
           else { PrefDir = w; AltDir1 = s; AltDir2 = n; BackDir = e }
       } else {
           if (SY > 0) { PrefDir = s; AltDir1 = e; AltDir2 = w; BackDir = n }
           else { PrefDir = n; AltDir1 = w; AltDir2 = e; BackDir = s }
       };
       !try_corridor_dir(PrefDir, AltDir1, AltDir2, BackDir).

+!do_corridor_explore(MX, MY)
    <- // Sem setor definido: direção aleatória
       .random(R);
       if (R < 0.25) { Dir = n }
       elif (R < 0.5) { Dir = e }
       elif (R < 0.75) { Dir = s }
       else { Dir = w };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

-!do_corridor_explore(_, _)
    <- .abolish(last_attempted_dir(_));
       +last_attempted_dir(n);
       action("move(n)").

// Tenta dir preferida, depois alternativas, evitando reverso do último move
+!try_corridor_dir(PrefDir, AltDir1, AltDir2, BackDir)
    <- .abolish(has_destination(_, _));
       !pick_corridor_move(PrefDir, AltDir1, AltDir2, BackDir).

+!pick_corridor_move(PrefDir, AltDir1, AltDir2, BackDir)
    <- // Tenta preferida se não bloqueada visualmente
       !get_dir_offset(PrefDir, PX, PY);
       if (not cell_blocked(PX, PY) & not is_bounce(PrefDir)) {
           ChosenDir = PrefDir
       } else {
           // Tenta alternativas (com jitter para não ficar preso em loops)
           !get_dir_offset(AltDir1, A1X, A1Y);
           !get_dir_offset(AltDir2, A2X, A2Y);
           .random(Jit);
           if (Jit < 0.5) { FirstAlt = AltDir1; FA_X = A1X; FA_Y = A1Y; SecondAlt = AltDir2; SA_X = A2X; SA_Y = A2Y }
           else { FirstAlt = AltDir2; FA_X = A2X; FA_Y = A2Y; SecondAlt = AltDir1; SA_X = A1X; SA_Y = A1Y };
           if (not cell_blocked(FA_X, FA_Y) & not is_bounce(FirstAlt)) {
               ChosenDir = FirstAlt
           } elif (not cell_blocked(SA_X, SA_Y) & not is_bounce(SecondAlt)) {
               ChosenDir = SecondAlt
           } elif (not cell_blocked(PX, PY)) {
               ChosenDir = PrefDir
           } else {
               !get_dir_offset(BackDir, BX, BY);
               if (not cell_blocked(BX, BY)) {
                   ChosenDir = BackDir
               } else {
                   ChosenDir = PrefDir
               }
           }
       };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(ChosenDir);
       .concat("move(", ChosenDir, ")", Act);
       action(Act).

-!pick_corridor_move(_, _, _, _)
    <- .abolish(last_attempted_dir(_));
       +last_attempted_dir(n);
       action("move(n)").

// Resolve offset de uma direção
+!get_dir_offset(n, 0, -1) <- true.
+!get_dir_offset(s, 0, 1) <- true.
+!get_dir_offset(e, 1, 0) <- true.
+!get_dir_offset(w, -1, 0) <- true.
-!get_dir_offset(_, 0, 0) <- true.

// ============================================================
// Escape reativo (#3 + #4 agindo) — camada 100% .asl
// Invocado pelos handlers de bloqueio (move falho / oscilacao).
// Legalidade pela percepcao local; ranking pela distancia toroidal
// do SharedMap (manhattan_dist), consistente com o A*.
// ============================================================

// offsets das 4 direcoes
dir_off(n, 0, -1).
dir_off(e, 1, 0).
dir_off(s, 0, 1).
dir_off(w, -1, 0).

// celula relativa (CX,CY) bloqueada por obstaculo/entidade/bloco-de-outro
cell_blocked(CX, CY) :- thing(CX, CY, obstacle, _).
cell_blocked(CX, CY) :- thing(CX, CY, entity, _).
cell_blocked(CX, CY) :- thing(CX, CY, block, _) & not attached(CX, CY).

// anti-volta: a direcao candidata e o reverso do ultimo movimento (= volta a celula-parceira da oscilacao)
is_bounce(n) :- last_attempted_dir(s).
is_bounce(s) :- last_attempted_dir(n).
is_bounce(e) :- last_attempted_dir(w).
is_bounce(w) :- last_attempted_dir(e).

// legalidade de uma direcao (offset OX,OY): celula do agente + futuros dos
// blocos anexados livres. Resultado deixado na crenca legal_ok.
+!compute_legal(OX, OY)
    <- .abolish(legal_ok);
       .abolish(dir_bad);
       .findall(att(AX, AY), attached(AX, AY), Atts);
       for (.member(att(BX, BY), Atts)) {
           BTX = BX + OX; BTY = BY + OY;
           if ((BTX \== 0 | BTY \== 0) & not attached(BTX, BTY) & cell_blocked(BTX, BTY)) {
               +dir_bad
           }
       };
       if (not cell_blocked(OX, OY) & not dir_bad) { +legal_ok };
       .abolish(dir_bad).
-!compute_legal(_, _) <- .abolish(dir_bad).

// pontua uma direcao: se legal e nao for a celula-parceira da oscilacao
// (osc_p2 = posicao do step anterior), calcula a distancia toroidal ao
// destino e registra esc_cand(Dir, D).
+!score_dir(MX, MY, GX, GY, Dir, OX, OY)
    <- !compute_legal(OX, OY);
       TX = MX + OX; TY = MY + OY;   // manhattan_dist normaliza internamente (toroidal) — independe do tamanho do grid
       if (legal_ok & not is_bounce(Dir)) {   // anti-volta por DIRECAO (reverso do ultimo move), sem hardcode de tamanho
           manhattan_dist(TX, TY, GX, GY, D);
           +esc_cand(Dir, D)
       };
       .abolish(legal_ok).
-!score_dir(_, _, _, _, _, _, _) <- .abolish(legal_ok).

// objetivo principal: escolher e executar a acao de escape
+!escape_move(MX, MY, GX, GY)
    <- .abolish(esc_cand(_, _));
       !score_dir(MX, MY, GX, GY, n, 0, -1);
       !score_dir(MX, MY, GX, GY, e, 1, 0);
       !score_dir(MX, MY, GX, GY, s, 0, 1);
       !score_dir(MX, MY, GX, GY, w, -1, 0);
       !pick_escape(MX, MY).
-!escape_move(_, _, _, _) <- .abolish(esc_cand(_, _)); action("skip").

// ha candidato legal: move ao mais proximo do destino (empate -> jitter)
+!pick_escape(MX, MY)
    : esc_cand(_, _)
    <- .findall(c(D, Dir), esc_cand(Dir, D), L);
       .min(L, c(MinD, _));
       .findall(TDir, esc_cand(TDir, MinD), Ties);
       .length(Ties, NT);
       .random(R);
       RIdx = math.floor(R * NT);
       .nth(RIdx, Ties, ChosenDir);
       .abolish(esc_cand(_, _));
       .abolish(boxed_count(_));
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(ChosenDir);
       .concat("move(", ChosenDir, ")", Act);
       action(Act).
// nenhum candidato legal util: encurralado
+!pick_escape(MX, MY)
    <- .abolish(esc_cand(_, _));
       !boxed_step(MX, MY).
-!pick_escape(_, _) <- .abolish(esc_cand(_, _)); action("skip").

// encurralado: ceder; apos K steps consecutivos, sacudir (quebra simetria)
+!boxed_step(MX, MY)
    <- if (boxed_count(C0)) { -boxed_count(C0); BC = C0 + 1 } else { BC = 1 };
       +boxed_count(BC);
       if (escape_shake_k(KK)) { Kv = KK } else { Kv = 3 };
       if (BC >= Kv) {
           .abolish(boxed_count(_)); +boxed_count(0);
           !shake(MX, MY)
       } else {
           action("skip")
       }.
-!boxed_step(_, _) <- action("skip").

// sacode: move aleatorio entre direcoes fisicamente legais (sem ranking/parceiro)
+!shake(MX, MY)
    <- !collect_free(MX, MY);
       .findall(FD, free_dir(FD), Free);
       .abolish(free_dir(_));
       .length(Free, NF);
       if (NF > 0) {
           .random(R2);
           RI = math.floor(R2 * NF);
           .nth(RI, Free, SD);
           .abolish(last_attempted_dir(_));
           +last_attempted_dir(SD);
           .concat("move(", SD, ")", SAct);
           action(SAct)
       } else {
           action("skip")
       }.
-!shake(_, _) <- action("skip").

+!collect_free(MX, MY)
    <- .abolish(free_dir(_));
       !mark_free(n, 0, -1);
       !mark_free(e, 1, 0);
       !mark_free(s, 0, 1);
       !mark_free(w, -1, 0).
-!collect_free(_, _) <- true.

+!mark_free(Dir, OX, OY)
    <- !compute_legal(OX, OY);
       if (legal_ok) { +free_dir(Dir) };
       .abolish(legal_ok).
-!mark_free(_, _, _) <- .abolish(legal_ok).
