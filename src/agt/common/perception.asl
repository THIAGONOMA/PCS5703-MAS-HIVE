// ============================================================
// perception.asl — Processamento generico de percepts
// ============================================================

// --- Grid dimensions (toroidal wrapping) ---

// #1+#2 (review Fase D): dims aplicadas SO no modo dev, no 1o +position (abaixo).
// No oficial (absolutePosition:false, sem percept 'position') as dims ficam 0 ->
// normX/normY viram identidade -> o mapa e o dr_pos vivem no MESMO frame nao-
// normalizado e o A* roda sem-wrap (KTD3, degradacao graciosa). Isso evita o
// modulo errado (apply_grid_config poria 40 num servidor 70x70 sem -PgridW) e o
// mismatch dr_pos(ilimitado)-vs-coord-normalizada que quebrava a chegada pos-wrap.
// A U4 (deferida) infere as dims reais do oficial depois.
+!try_set_grid_dims <- true.

// --- Posicao: dev usa o percept 'position'; no oficial (absolutePosition:false,
// sem percept) cai para dead-reckoning em dr_pos (Fase D / keystone U2). ---
//
// dr_pos é observable property do EISAccess artifact (DR em Java).
my_pos(X, Y) :- position(X, Y).
my_pos(X, Y) :- not position(_, _) & dr_pos(X, Y).

// dev (ha percept 'position'): aplica as dims do GridConfig 1x (origem: -PgridW/H
// ou default 40). No oficial este plano nunca dispara, logo dims ficam 0 (ver
// try_set_grid_dims acima).
+position(X, Y) : not grid_dims_applied
    <- +grid_dims_applied; apply_grid_config; !on_pos_update(X, Y).
+position(X, Y) <- !on_pos_update(X, Y).

// cascata por-posicao (extraida p/ reuso pelo caminho dead-reckoned do oficial).
+!on_pos_update(X, Y)
    <- .abolish(escape_pending(_, _));
       mark_visited(X, Y);
       mark_vision_visited(X, Y, 5);
       .my_name(Me);
       !try_update_pos(Me, X, Y);
       !dash_step_safe;
       !check_stuck(X, Y);
       !check_osc(X, Y);
       !try_merge_scan;
       !periodic_cleanup.
-!on_pos_update(_, _) <- true.

// no oficial (sem percept 'position') a cascata roda 1x/step via lastActionResult.
+!offline_cascade : not position(_, _) & dr_pos(X, Y) <- !on_pos_update(X, Y).
+!offline_cascade <- true.

// DR via artifact: quando dr_pos muda, rodar cascata de posição
+dr_pos(X, Y) : not position(_, _)
    <- !on_pos_update(X, Y).

// DR agora é feito no EISAccess.java; handler mantido como no-op por segurança.
+!dead_reckon_move <- true.

+!check_stuck(X, Y)
    : stuck_since(SX, SY, SStep) & step(N) & SX == X & SY == Y
      & (N - SStep >= 50) & (pending_submit(_) | solo_mode(_))
      & attached(AX, AY)
    <- .abolish(stuck_since(_, _, _));
       +stuck_since(X, Y, N);
       if (AY == -1) { DDir = n }
       elif (AY == 1) { DDir = s }
       elif (AX == 1) { DDir = e }
       else { DDir = w };
       .print("[STUCK] Marcando detach necessario dir=", DDir);
       +need_detach(DDir).

+!check_stuck(X, Y)
    : stuck_since(SX, SY, _) & (SX \== X | SY \== Y) & step(N)
    <- .abolish(stuck_since(_, _, _));
       +stuck_since(X, Y, N).

+!check_stuck(X, Y)
    : not stuck_since(_, _, _) & step(N)
    <- +stuck_since(X, Y, N).

+!check_stuck(_, _) <- true.
-!check_stuck(_, _) <- true.

// --- Detecção de oscilação A<->B (#4) ---
// Exige 3+ ping-pongs consecutivos antes de disparar escape.
// Evita acusar contorno legítimo como oscilação.

+!check_osc(X, Y)
    : osc_p2(X2, Y2) & X == X2 & Y == Y2
      & osc_p1(X1, Y1) & (X \== X1 | Y \== Y1)
      & step(N)
    <- if (osc_count(OC)) { -osc_count(OC); NOC = OC + 1 } else { NOC = 1 };
       +osc_count(NOC);
       if (NOC >= 3 & has_destination(DX, DY)) {
           .print("[OSC] ping-pong x", NOC, " (", X, ",", Y, ")<->(", X1, ",", Y1, ") step ", N);
           .abolish(escape_pending(_, _));
           +escape_pending(X, Y);
           -osc_count(_)
       };
       !osc_shift(X, Y).
+!check_osc(X, Y)
    <- .abolish(osc_count(_));
       !osc_shift(X, Y).
-!check_osc(_, _) <- true.

+!osc_shift(X, Y)
    <- if (osc_p1(PX, PY)) { .abolish(osc_p2(_, _)); +osc_p2(PX, PY) };
       .abolish(osc_p1(_, _)); +osc_p1(X, Y).
-!osc_shift(_, _) <- true.

+!try_update_pos(Me, X, Y)
    <- update_agent_pos(Me, X, Y);
       if (step(S)) { update_occupancy(Me, X, Y, S) }
       else { update_occupancy(Me, X, Y, 0) }.
-!try_update_pos(_, _, _) <- true.

// --- Things ---

+thing(X, Y, Type, Details)
    : my_pos(MX, MY) & Type == dispenser
    <- update_cell(MX + X, MY + Y, Type, Details);
       !dash_map_dispenser(MX + X, MY + Y, Details).

+thing(X, Y, Type, Details)
    : my_pos(MX, MY)
    <- update_cell(MX + X, MY + Y, Type, Details);
       !mark_entity_occupancy(Type, Details, X, Y, MX, MY).

// Fase D / U5: sem frame global, o overlay #2 evita entidades PERCEBIDAS
// (alcance de visao) no frame local. Chave por celula; expira sozinha (snapshot).
// #4: nao penaliza entidade de time INIMIGO confirmado (R8 = colega) — 'Details'
// e o time da entidade, 'my_team(MyTeam)' o nosso (persistido do percept SIM-START
// 'team', que o EIS apaga apos o step 1 — por isso my_team, nao team). Guard
// conservador: so pula quando SABE que e inimigo; se my_team ainda nao esta bound,
// marca (degrada seguro, sem re-desligar o overlay e reabrir o livelock).
+!mark_entity_occupancy(entity, Team, RX, RY, MX, MY)
    : not (RX == 0 & RY == 0) & step(N) & not (my_team(MyTeam) & Team \== MyTeam)
    <- EX = MX + RX; EY = MY + RY;
       .concat("seen_", EX, "_", EY, K);
       update_occupancy(K, EX, EY, N).
+!mark_entity_occupancy(_, _, _, _, _, _) <- true.

// --- Zonas ---

+goalZone(X, Y)
    : my_pos(MX, MY)
    <- update_cell(MX + X, MY + Y, "goal_zone", "");
       !dash_map_goal_zone(MX + X, MY + Y).

+roleZone(X, Y)
    : my_pos(MX, MY)
    <- update_cell(MX + X, MY + Y, "role_zone", "").

// --- Tasks ---

+task(Name, Deadline, Reward, Reqs)
    <- .length(Reqs, NBlocks);
       -known_task(Name, _, _, _);
       +known_task(Name, Deadline, Reward, NBlocks);
       .abolish(task_req(Name, _, _, _));
       !try_register_task(Name, Deadline, Reward, NBlocks);
       for (.member(req(RX, RY, RT), Reqs)) {
           +task_req(Name, RX, RY, RT);
           register_task_block(Name, RT)
       };
       signal_task_ready(Name).

+!try_register_task(Name, Deadline, Reward, NBlocks)
    <- register_task(Name, Deadline, Reward, NBlocks).
-!try_register_task(_, _, _, _) <- true.

// --- Normas ---

+norm(Id, Start, End, Reqs, Fine)
    <- +active_norm(Id, Start, End, Reqs, Fine);
       !check_carry_norm(Reqs).

-norm(Id, _, _, _, _)
    <- .abolish(active_norm(Id, _, _, _, _));
       .abolish(carry_limit(_)).

+!check_carry_norm(Reqs)
    <- for (.member(requirement(block, _, Qty, _), Reqs)) {
           if (not carry_limit(Qty)) {
               .abolish(carry_limit(_));
               +carry_limit(Qty)
           }
       }.
-!check_carry_norm(_) <- true.

norm_allows_carry :- not carry_limit(_).
norm_allows_carry :- carry_limit(Limit) & .count(attached(_, _), N) & N < Limit.

// --- Score ---

+score(S)
    <- -my_score(_); +my_score(S);
       !dash_score(S).

// --- Energia ---

+energy(E)
    <- -my_energy(_); +my_energy(E);
       if (E < 10) {
           .concat("{\"energy\":", E, "}", EJ);
           !dash_log("low_energy", EJ)
       }.

// --- Desativacao ---

+deactivated(true)
    <- -am_active; +am_deactivated;
       .print("*** DESATIVADO! Aguardando reativacao ***");
       !dash_log("deactivated", "{}").

+deactivated(false)
    : am_deactivated
    <- -am_deactivated; +am_active;
       .print("*** REATIVADO! Voltando ao normal ***");
       !dash_log("reactivated", "{}").

// --- Role ---

// P0: ao receber o role corrente, se for capaz de coletar/submeter, encerra a
// necessidade de adocao (role_capable/1 definido em role_adoption.asl).
+role(R)
    <- -my_role(_); +my_role(R);
       if (role_capable(R) & need_role_adoption) {
           -need_role_adoption;
           .print("[ROLE] Adotei ", R, " — habilitado para coletar/submeter")
       }.

// --- Resultado de acao (tracking) ---

// DR agora é processado via +step(N) handler em perception.asl (acima).
// Estes handlers fazem tracking de blocked/cascata mas NÃO atualizam DR.

+lastActionResult(failed_path)
    <- +last_move_blocked;
       !offline_cascade.

+lastActionResult(failed)
    <- !offline_cascade.

+lastActionResult(success)
    <- -last_move_blocked;
       !offline_cascade.

// P0: role corrente nao permite a acao tentada (cenario oficial). Marca a
// necessidade de adotar 'worker' numa role zone. So ocorre no oficial — no dev
// 'default' tem todas as acoes, entao nunca dispara (auto-deteccao de modo).
+lastActionResult(failed_role)
    <- if (not need_role_adoption) {
           .print("[ROLE] failed_role: role atual nao permite a acao — preciso adotar worker");
           +need_role_adoption;
           .abolish(collecting(_, _, _));
           .abolish(waiting_request(_, _));
           .abolish(waiting_attach_result(_, _));
           .abolish(searching_dispenser(_))
       };
       !offline_cascade.

// outros codigos de resultado (sem handler especifico): ainda rodam a cascata 1x/step no oficial.
+lastActionResult(_) <- !offline_cascade.

// --- Blocos attached ---

+attached(X, Y)
    <- -my_attached(X, Y); +my_attached(X, Y).

-attached(X, Y)
    <- -my_attached(X, Y).

carrying_blocks(N) :- .count(my_attached(_, _), N).
has_block :- my_attached(_, _).

+!periodic_cleanup : step(N) & (N mod 50) == 0
    <- !check_expired_task;
       decay_obstacles(N);
       remove_expired(N);
       !try_periodic_remerge.
+!periodic_cleanup : step(N) & (N mod 10) == 0
    <- !check_expired_task;
       decay_obstacles(N).
+!periodic_cleanup
    <- !check_expired_task.
-!periodic_cleanup <- true.
