// ============================================================
// map_merge.asl — Fusão de mapas cross-agente (U9)
// ============================================================
// Protocolo otimizado: broadcast SÓ quando vejo teammate sem
// offset conhecido. Após estabelecer offset, compartilha
// discoveries UMA VEZ (não fica re-pedindo em loop).
// ============================================================

// --- Handshake: scan de teammates visíveis ---

// Só broadcast quando vejo teammate para quem NÃO tenho offset.
// Usa .send direto ao invés de .broadcast para reduzir overhead.
+!try_merge_scan
    : my_pos(MX, MY) & my_team(MyTeam) & step(N) & (N mod 10) == 0
      & thing(RX, RY, entity, MyTeam) & (RX \== 0 | RY \== 0)
      & not merge_scan_step(N)
    <- .abolish(merge_scan_step(_));
       +merge_scan_step(N);
       // Conta quantos offsets já tenho — se muitos, não vale o custo
       .count(known_offset(_, _, _), NOff);
       if (NOff < 10) {
           .my_name(Me);
           .broadcast(tell, i_see_mate(Me, N, MX, MY, RX, RY))
       }.
+!try_merge_scan <- true.
-!try_merge_scan <- true.

// --- Re-merge periódico (a cada 200 steps, só 1 mate por vez) ---
+!try_periodic_remerge
    : step(N) & (N mod 200) == 100 & known_offset(MN, _, _)
    <- .my_name(Me);
       .send(MN, tell, request_discoveries(Me)).
+!try_periodic_remerge <- true.
-!try_periodic_remerge <- true.

// --- Recepção de broadcast: verificar reciprocidade ---

+i_see_mate(TheirName, TheirStep, TheirX, TheirY, TheirRX, TheirRY)[source(S)]
    : .my_name(Me) & Me \== TheirName
      & not known_offset(TheirName, _, _)
      & my_pos(MX, MY) & step(MyStep)
    <- ExpRX = -TheirRX; ExpRY = -TheirRY;
       if (thing(ExpRX, ExpRY, entity, _)) {
           DX = MX + ExpRX - TheirX;
           DY = MY + ExpRY - TheirY;
           +known_offset(TheirName, DX, DY);
           .print("[MERGE] Offset com ", TheirName, ": dX=", DX, " dY=", DY, " (step ", MyStep, ")");
           .send(TheirName, tell, request_discoveries(Me))
       };
       .abolish(i_see_mate(TheirName, _, _, _, _, _)[source(_)]).

// Offset já conhecido: descartar sem processar
+i_see_mate(TheirName, _, _, _, _, _)[source(S)]
    <- .abolish(i_see_mate(TheirName, _, _, _, _, _)[source(_)]).

// --- Compartilhamento de discoveries ---

+request_discoveries(RequesterName)[source(S)]
    <- .abolish(request_discoveries(RequesterName)[source(_)]);
       !send_my_discoveries(RequesterName).

+!send_my_discoveries(RequesterName)
    <- .findall(disp(X, Y, T), known_dispenser(X, Y, T), Disps);
       .findall(gz(X, Y), known_goal_zone(X, Y), Goals);
       .findall(rz(X, Y), known_role_zone(X, Y), Roles);
       .length(Disps, ND); .length(Goals, NG); .length(Roles, NR);
       if (ND > 0 | NG > 0 | NR > 0) {
           .my_name(Me);
           .send(RequesterName, tell, remote_discoveries(Me, Disps, Goals, Roles));
           .print("[MERGE] Enviei ", ND, "d ", NG, "g ", NR, "r para ", RequesterName)
       }.
-!send_my_discoveries(_) <- true.

// Receber discoveries e importar traduzidas para meu frame
+remote_discoveries(SenderName, Disps, Goals, Roles)[source(S)]
    : known_offset(SenderName, DX, DY)
    <- .abolish(remote_discoveries(SenderName, _, _, _)[source(_)]);
       for (.member(disp(X, Y, T), Disps)) {
           TX = X + DX; TY = Y + DY;
           import_dispenser(TX, TY, T)
       };
       for (.member(gz(X, Y), Goals)) {
           TX = X + DX; TY = Y + DY;
           import_goal_zone(TX, TY)
       };
       for (.member(rz(X, Y), Roles)) {
           TX = X + DX; TY = Y + DY;
           import_role_zone(TX, TY)
       };
       .length(Disps, ND); .length(Goals, NG); .length(Roles, NR);
       .print("[MERGE] Importei de ", SenderName, ": ", ND, "d ", NG, "g ", NR, "r").

// Fallback: descartar discoveries sem offset
+remote_discoveries(SenderName, _, _, _)[source(S)]
    <- .abolish(remote_discoveries(SenderName, _, _, _)[source(_)]).
