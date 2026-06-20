// ============================================================
// connect_protocol.asl — Protocolo de connect sincronizado + submit
// Incluir ANTES de collection.asl para prioridade maxima de +step(N)
// ============================================================

// #52: bloco attached ja satisfaz o requisito da task (posicao identica).
block_already_aligned(TaskName) :-
    task_req(TaskName, RX, RY, _) &
    attached(RX, RY).

// --- MULTI-BLOCK: recrutamento de parceiro via connect ---
// Intercepta collected_block ANTES dos handlers role-specific.
// Após coletar o 1o bloco de um 2-block task, recruta um parceiro
// que coleta o 2o bloco e faz connect na geometria correta.

// Primeiro bloco coletado (2-block task) → recrutar parceiro
// Usa solo_saved_req (armazenado no self-assign) para evitar race condition
// com +task() que pode abolish task_req temporariamente.
+collected_block(Type)
    : solo_mode(TaskName) & solo_blocks_needed(2) & solo_blocks_collected(0)
      & my_pos(MX, MY)
    <- -solo_blocks_collected(0); +solo_blocks_collected(1);
       .findall(req(RX,RY,RT), solo_saved_req(RX, RY, RT), Reqs);
       if (.length(Reqs, NR) & NR < 2) {
           .findall(req(RX2,RY2,RT2), task_req(TaskName, RX2, RY2, RT2), Reqs2);
           if (.length(Reqs2, NR2) & NR2 >= 2) { UseReqs = Reqs2 }
           else { UseReqs = [] }
       } else {
           UseReqs = Reqs
       };
       .length(UseReqs, FinalLen);
       if (FinalLen >= 2) {
           .nth(0, UseReqs, req(R0X, R0Y, R0T));
           .nth(1, UseReqs, req(R1X, R1Y, R1T));
           if (R0X == 0 & R0Y == 1) {
               SecType = R1T; B2X = R1X; B2Y = R1Y
           } else {
               SecType = R0T; B2X = R0X; B2Y = R0Y
           };
           get_nearest_goal_zone(MX, MY, GZX, GZY);
           if (GZX \== -1) {
               .my_name(Me);
               .abolish(has_destination(_, _));
               +has_destination(GZX, GZY);
               +awaiting_partner(TaskName, SecType, GZX, GZY, B2X, B2Y);
               .broadcast(tell, need_partner(Me, TaskName, SecType, GZX, GZY, B2X, B2Y));
               .print("[MULTI] 1o bloco OK. Recrutando parceiro para ", SecType,
                       " tarefa=", TaskName, " gzone=(", GZX, ",", GZY, ") blk2=(", B2X, ",", B2Y, ")")
           } else {
               .print("[MULTI] Sem goal zone. Submit solo.");
               +pending_submit(TaskName)
           }
       } else {
           .print("[MULTI] Reqs inconsistentes. Submit com o que tem: ", TaskName);
           +pending_submit(TaskName);
           get_nearest_goal_zone(MX, MY, GX, GY);
           if (GX \== -1) {
               .abolish(has_destination(_, _));
               +has_destination(GX, GY)
           }
       }.

// --- PARCEIRO: aceitar pedido de recrutamento ---
+need_partner(SubmitterName, TaskName, BlockType, GZX, GZY, B2X, B2Y)[source(S)]
    : not my_active_task(_, _) & not collecting(_, _, _)
      & not pending_submit(_) & not navigating_to_meeting_point(_)
      & not partner_role(_, _)
      & not need_role_adoption
    <- .my_name(Me);
       if (Me \== SubmitterName) {
           .print("[PARTNER] Aceito parceria com ", SubmitterName, " para ", TaskName, " bloco=", BlockType);
           mark_busy(Me);
           .abolish(collecting(_, _, _));
           .abolish(has_destination(_, _));
           .abolish(waiting_request(_, _));
           .abolish(waiting_attach_result(_, _));
           .abolish(collected_block(_));
           +my_active_task(TaskName, "partner");
           +partner_role(SubmitterName, TaskName);
           +partner_target_pos(GZX, GZY, B2X, B2Y);
           .send(SubmitterName, tell, partner_accepted(Me, TaskName));
           !collect_block(BlockType)
       }.

// Parceiro já ocupado → ignorar
+need_partner(_, _, _, _, _, _, _) <- true.

// Submitter recebe confirmação do parceiro
+partner_accepted(PartnerName, TaskName)[source(S)]
    : awaiting_partner(TaskName, _, _, _, _, _)
    <- .print("[MULTI] Parceiro ", PartnerName, " aceitou para ", TaskName);
       -awaiting_partner(TaskName, _, _, _, _, _);
       +confirmed_partner(PartnerName, TaskName).

// Parceiro coletou bloco → rotacionar para (0,-1) e navegar ao offset
+collected_block(Type)
    : partner_role(SubmitterName, TaskName) & partner_target_pos(GZX, GZY, B2X, B2Y)
      & my_pos(MX, MY)
    <- .print("[PARTNER] Bloco ", Type, " coletado. Rotacionando e navegando para connect.");
       +partner_block_collected(Type);
       TargetX = GZX + B2X;
       TargetY = GZY + B2Y + 1;
       .abolish(has_destination(_, _));
       +has_destination(TargetX, TargetY);
       +partner_connect_target(TargetX, TargetY);
       .print("[PARTNER] Navegando para (", TargetX, ",", TargetY, ") para connect com ", SubmitterName).

// Parceiro: rotacionar bloco para (0,-1) antes do connect
+step(N)
    : partner_role(_, _) & partner_block_collected(_)
      & partner_connect_target(TX, TY) & my_pos(MX, MY)
      & MX == TX & MY == TY
      & attached(AX, AY) & (AX \== 0 | AY \== -1)
    <- .print("[PARTNER] Rotacionando bloco de (", AX, ",", AY, ") para (0,-1)");
       action("rotate(cw)").

// Parceiro: no ponto alvo com bloco em (0,-1) → sinalizar pronto
+step(N)
    : partner_role(SubmitterName, TaskName) & partner_block_collected(_)
      & partner_connect_target(TX, TY) & my_pos(MX, MY)
      & MX == TX & MY == TY
      & attached(0, -1)
    <- .my_name(Me);
       .print("[PARTNER] Pronto para connect com ", SubmitterName);
       .send(SubmitterName, tell, partner_ready(Me, TaskName));
       +partner_signaled_ready.

// Submitter recebe sinal de parceiro pronto → armar belief para +step
+partner_ready(PartnerName, TaskName)[source(S)]
    : confirmed_partner(PartnerName, TaskName)
    <- .print("[MULTI] Parceiro ", PartnerName, " pronto para connect.");
       +do_connect_with_partner(PartnerName, TaskName).

+partner_ready(_, _) <- true.

// Submitter: cada step, tenta connect quando no goal zone com parceiro pronto
+step(N)
    : do_connect_with_partner(PartnerName, TaskName)
      & goalZone(0, 0) & attached(AX, AY) & my_pos(MX, MY)
    <- -do_connect_with_partner(PartnerName, TaskName);
       .concat("connect(", PartnerName, ",", AX, ",", AY, ")", Act);
       action(Act);
       +waiting_connect_result(PartnerName, TaskName);
       .print("[MULTI] Step ", N, ": Connect(", PartnerName, ",", AX, ",", AY, ")").

// Submitter: não no goal zone → skip (continua navegando no handler de pending_submit)
+step(N)
    : do_connect_with_partner(_, _) & not goalZone(0, 0) & my_pos(MX, MY)
    <- true.

// Parceiro: cada step no ponto alvo com bloco em (0,-1) → fire connect
+step(N)
    : partner_role(SubmitterName, _) & partner_signaled_ready
      & attached(0, -1)
    <- .concat("connect(", SubmitterName, ",0,-1)", Act);
       action(Act);
       .print("[PARTNER] Step ", N, ": Connect com ", SubmitterName).

// Connect sucesso do parceiro → liberar
+step(N)
    : partner_role(SubmitterName, TaskName)
      & lastAction(connect) & lastActionResult(success)
    <- .print("[PARTNER] Connect OK! Bloco transferido.");
       .my_name(Me);
       mark_free(Me);
       .abolish(partner_role(_, _));
       .abolish(partner_target_pos(_, _, _, _));
       .abolish(partner_connect_target(_, _));
       .abolish(partner_block_collected(_));
       .abolish(partner_signaled_ready);
       .abolish(my_active_task(_, _));
       .abolish(confirmed_partner(_, _));
       .abolish(has_destination(_, _));
       .abolish(do_connect_with_partner(_, _));
       !do_explore(0, 0).

// Connect falha do parceiro → retentar no próximo step (automaticamente pelo handler acima)
+step(N)
    : partner_role(SubmitterName, _)
      & lastAction(connect) & lastActionResult(R) & R \== success
    <- .print("[PARTNER] Step ", N, ": Connect falhou (", R, "). Retentando...").

// Submitter: connect sucesso → submit
// (tratado pelo handler existente de waiting_connect_result, line ~652)

// --- DESATIVADO: nao fazer nada ---

+step(N)
    : am_deactivated
    <- action("skip").

// --- ENERGIA BAIXA: priorizar sobrevivencia ---

+step(N)
    : my_energy(E) & E < 5 & not am_deactivated & my_pos(MX, MY)
    <- .print("[ENERGY] Step ", N, ": Energia critica (", E, ")! Skip para conservar.");
       action("skip").

// --- CLEAR BLOCKS: detach stale blocks before new collection (only adjacent) ---

+step(N) : needs_clear_blocks(Type) & attached(0, -1) <- action("detach(n)").
+step(N) : needs_clear_blocks(Type) & attached(0, 1) <- action("detach(s)").
+step(N) : needs_clear_blocks(Type) & attached(1, 0) <- action("detach(e)").
+step(N) : needs_clear_blocks(Type) & attached(-1, 0) <- action("detach(w)").

+step(N)
    : needs_clear_blocks(Type) & attached(_, _)
    <- action("rotate(cw)").

+step(N)
    : needs_clear_blocks(Type)
    <- -needs_clear_blocks(Type);
       !collect_block(Type).

// --- NORM VIOLATION: detach excess blocks to avoid penalty ---
// #51: (a) só detach de bloco cardinal-adjacente (|dx|+|dy|==1);
//      (b) cede ao submit quando pending_submit + goalZone (submit consome 1 bloco e resolve a violação).

+step(N)
    : carry_limit(Limit) & .count(attached(_, _), NumAtt) & NumAtt > Limit
      & not (pending_submit(_) & goalZone(0, 0))
      & not submitted_task(_) & not collecting(_, _, _)
      & not collected_block(_)
      & attached(AX, AY) & (math.abs(AX) + math.abs(AY) == 1)
    <- .abolish(norm_rotate_count(_));
       if (AY == -1) { DDir = n }
       elif (AY == 1) { DDir = s }
       elif (AX == 1) { DDir = e }
       else { DDir = w };
       .print("[NORM] Step ", N, ": Detach excess block dir=", DDir, " (limit=", Limit, " att=", NumAtt, ")");
       .concat("detach(", DDir, ")", Act); action(Act).

// #51: bloco excedente em posição diagonal — rotacionar (max 4x, depois desiste)
+step(N)
    : carry_limit(Limit) & .count(attached(_, _), NumAtt) & NumAtt > Limit
      & not (pending_submit(_) & goalZone(0, 0))
      & not submitted_task(_) & not collecting(_, _, _)
      & not collected_block(_)
      & attached(_, _) & norm_rotate_count(NRC) & NRC >= 4
    <- .print("[NORM] Step ", N, ": Excess diagonal block irresolvivel apos 4 rotacoes. Prosseguindo.");
       .abolish(norm_rotate_count(_)).

+step(N)
    : carry_limit(Limit) & .count(attached(_, _), NumAtt) & NumAtt > Limit
      & not (pending_submit(_) & goalZone(0, 0))
      & not submitted_task(_) & not collecting(_, _, _)
      & not collected_block(_)
      & attached(_, _)
    <- if (norm_rotate_count(OldNRC)) { .abolish(norm_rotate_count(_)); NRC = OldNRC + 1 }
       else { NRC = 1 };
       +norm_rotate_count(NRC);
       .print("[NORM] Step ", N, ": Excess block not cardinal-adjacent, rotating (", NRC, "/4) (limit=", Limit, " att=", NumAtt, ")");
       action("rotate(cw)").

// --- PRE-SUBMIT: detach excess blocks beyond task requirement ---

// 2-block: detach se > 2 attached
+step(N)
    : pending_submit(TaskName) & not submitted_task(_)
      & solo_mode(_) & solo_blocks_needed(2)
      & .count(attached(_, _), NumAtt) & NumAtt > 2
      & attached(AX, AY) & (math.abs(AX) + math.abs(AY) == 1)
    <- if (AY == -1) { DDir = n }
       elif (AY == 1) { DDir = s }
       elif (AX == 1) { DDir = e }
       else { DDir = w };
       .print("[SUBMIT] Detach excess 2b (att=", NumAtt, ") dir=", DDir);
       .concat("detach(", DDir, ")", Act); action(Act).

+step(N)
    : pending_submit(TaskName) & not submitted_task(_)
      & solo_mode(_) & solo_blocks_needed(2)
      & .count(attached(_, _), NumAtt) & NumAtt > 2
      & attached(AX, AY) & (math.abs(AX) + math.abs(AY) > 1)
    <- action("rotate(cw)").

// 1-block (ou sem info): detach se > 1 attached
+step(N)
    : pending_submit(TaskName) & not submitted_task(_)
      & solo_mode(_) & not solo_blocks_needed(2)
      & .count(attached(_, _), NumAtt) & NumAtt > 1
      & attached(AX, AY) & (math.abs(AX) + math.abs(AY) == 1)
    <- if (AY == -1) { DDir = n }
       elif (AY == 1) { DDir = s }
       elif (AX == 1) { DDir = e }
       else { DDir = w };
       .print("[SUBMIT] Detach excess 1b (att=", NumAtt, ") dir=", DDir);
       .concat("detach(", DDir, ")", Act); action(Act).

+step(N)
    : pending_submit(TaskName) & not submitted_task(_)
      & solo_mode(_) & not solo_blocks_needed(2)
      & .count(attached(_, _), NumAtt) & NumAtt > 1
      & attached(AX, AY) & (math.abs(AX) + math.abs(AY) > 1)
    <- action("rotate(cw)").

// --- SELF-ASSIGN: idle agents pick up tasks autonomously ---
// Aceita tasks de 1 ou 2 blocos. Para 2 blocos, coleta sequencialmente.
// Guard: requer pelo menos 1 goal zone conhecida.

// 1-block tasks
+step(N)
    : (N mod 5) == 3
      & not my_active_task(_, _) & not collecting(_, _, _)
      & not pending_submit(_) & not submitted_task(_)
      & not needs_clear_blocks(_) & not searching_dispenser(_)
      & not navigating_to_meeting_point(_) & not navigating_to_meeting_for_connect(_, _, _)
      & not waiting_connect_collector(_) & not waiting_connect_result(_, _)
      & not pending_connect(_, _, _, _) & not ready_to_connect(_, _, _, _)
      & not partner_role(_, _) & not awaiting_partner(_, _, _, _, _, _)
      & my_pos(MX, MY) & step(CS)
      & known_task(TN, TD, _, 1) & TD - CS > 40
      & task_req(TN, _, _, BType)
      & not need_role_adoption
    <- !try_self_assign(TN, TD, BType, 1, N, CS, MX, MY).

// 2-block tasks (quando não há 1-block)
+step(N)
    : (N mod 5) == 3
      & not my_active_task(_, _) & not collecting(_, _, _)
      & not pending_submit(_) & not submitted_task(_)
      & not needs_clear_blocks(_) & not searching_dispenser(_)
      & not navigating_to_meeting_point(_) & not navigating_to_meeting_for_connect(_, _, _)
      & not waiting_connect_collector(_) & not waiting_connect_result(_, _)
      & not pending_connect(_, _, _, _) & not ready_to_connect(_, _, _, _)
      & not partner_role(_, _) & not awaiting_partner(_, _, _, _, _, _)
      & my_pos(MX, MY) & step(CS)
      & known_task(TN, TD, _, 2) & TD - CS > 80
      & task_req(TN, _, _, BType)
      & not need_role_adoption
    <- .findall(req(RX,RY,RT), task_req(TN, RX, RY, RT), AllReqs);
       if (.length(AllReqs, AL) & AL >= 1) {
           .nth(0, AllReqs, req(_, _, FirstBT));
           !try_self_assign(TN, TD, FirstBT, 2, N, CS, MX, MY, AllReqs)
       } else {
           !try_self_assign(TN, TD, BType, 2, N, CS, MX, MY, AllReqs)
       }.

+!try_self_assign(TN, TD, BType, NBlocks, N, CS, MX, MY)
    <- !try_self_assign(TN, TD, BType, NBlocks, N, CS, MX, MY, []).

+!try_self_assign(TN, TD, BType, NBlocks, N, CS, MX, MY, SavedReqs)
    <- get_nearest_goal_zone(MX, MY, GZX, GZY);
       if (GZX == -1) {
           action("skip")
       } else {
           .my_name(Me);
           mark_busy(Me);
           .abolish(collecting(_, _, _));
           .abolish(has_destination(_, _));
           .abolish(waiting_request(_, _));
           .abolish(waiting_attach_result(_, _));
           .abolish(collected_block(_));
           .abolish(solo_mode(_));
           .abolish(solo_block_type(_));
           .abolish(solo_blocks_needed(_));
           .abolish(solo_blocks_collected(_));
           .abolish(request_retries(_, _));
           .abolish(task_accepted_step(_, _));
           .abolish(my_task_deadline(_, _));
           .abolish(searching_dispenser(_));
           .abolish(solo_saved_req(_, _, _));
           +my_task_deadline(TN, TD);
           +my_active_task(TN, "solo");
           +solo_mode(TN);
           +solo_block_type(BType);
           +solo_blocks_needed(NBlocks);
           +solo_blocks_collected(0);
           +task_accepted_step(TN, CS);
           for (.member(req(SRX, SRY, SRT), SavedReqs)) {
               +solo_saved_req(SRX, SRY, SRT)
           };
           .print("[SELF] Step ", N, ": Auto-assigned ", TN, " type=", BType, " blocks=", NBlocks, " dl=", TD, " goalzone=(", GZX, ",", GZY, ")");
           if (attached(_, _)) {
               +needs_clear_blocks(BType);
               action("skip")
           } else {
               !collect_block(BType)
           }
       }.
-!try_self_assign(_, _, _, _, _, _, _, _, _) <- action("skip").
-!try_self_assign(_, _, _, _, _, _, _, _) <- action("skip").

// --- SUBMIT: pending_submit e na goal zone ---

+step(N)
    : pending_submit(TaskName) & goalZone(0, 0) & not submitted_task(_)
    <- -pending_submit(TaskName);
       +submitted_task(TaskName);
       if (not submit_rotate_count(TaskName, _)) {
           +submit_rotate_count(TaskName, 0)
       };
       .findall(att(AX,AY), attached(AX,AY), AttList);
       .findall(treq(RX,RY,RT), task_req(TaskName, RX, RY, RT), ReqList);
       .print("[SUBMIT] Step ", N, ": submit(", TaskName, ") attached=", AttList, " reqs=", ReqList);
       .concat("submit(", TaskName, ")", Act);
       action(Act);
       .concat("{\"task\":\"", TaskName, "\"}", SJson);
       !dash_log("submit_attempt", SJson);
       !dash_task_phase(TaskName, "submit", 50).

// --- SUBMIT RESULT: sucesso → re-submit ou finalizar ---

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(success) & attached(_, _)
    <- .print("[SUBMIT] Step ", N, ": Submit de ", TaskName, " SUCESSO! Bloco ainda attached, re-submetendo...");
       .concat("{\"task\":\"", TaskName, "\",\"result\":\"success\"}", SSJson);
       !dash_log("submit_success", SSJson);
       -submitted_task(TaskName);
       +pending_submit(TaskName);
       action("skip").

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(success)
      & solo_block_type(BType) & my_task_deadline(TaskName, Deadline) & N + 40 < Deadline
    <- .print("[SUBMIT] Step ", N, ": Submit SUCESSO! Re-coletando ", BType, " (deadline=", Deadline, ")");
       .concat("{\"task\":\"", TaskName, "\",\"result\":\"success\"}", SSJson);
       !dash_log("submit_success", SSJson);
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       .abolish(submit_reposition_count(TaskName, _));
       .abolish(collected_block(_));
       .abolish(pending_submit(_));
       .abolish(has_destination(_, _));
       .abolish(nav_block_count(_));
       .abolish(collecting(_, _, _));
       .abolish(waiting_request(_, _));
       .abolish(waiting_attach_result(_, _));
       .abolish(request_retries(_, _));
       .abolish(task_accepted_step(_, _));
       .abolish(solo_blocks_collected(_));
       +solo_blocks_collected(0);
       +task_accepted_step(TaskName, N);
       // Para 2-block, re-coletar o tipo do primeiro bloco (task_req(TN, 0, 1, _))
       if (solo_blocks_needed(2)) {
           .findall(req(RX,RY,RT), task_req(TaskName, RX, RY, RT), Reqs);
           if (.length(Reqs, NR) & NR >= 2) {
               .nth(0, Reqs, req(R0X, R0Y, R0T));
               .nth(1, Reqs, req(R1X, R1Y, R1T));
               if (R0X == 0 & R0Y == 1) { FirstType = R0T }
               else { FirstType = R1T };
               .abolish(solo_block_type(_));
               +solo_block_type(FirstType);
               !collect_block(FirstType)
           } else { !collect_block(BType) }
       } else {
           !collect_block(BType)
       };
       action("skip").

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(success)
    <- if (solo_block_type(SBT)) { SBTInfo = SBT } else { SBTInfo = "NONE" };
       if (known_task(TaskName, KDL, _, _)) { DLInfo = KDL } else { DLInfo = -1 };
       .print("[SUBMIT] Step ", N, ": Submit de ", TaskName, " SUCESSO! Bloco consumido, finalizando. (solo_block_type=", SBTInfo, " deadline=", DLInfo, ")");
       .concat("{\"task\":\"", TaskName, "\",\"result\":\"success\"}", SSJson);
       !dash_log("submit_success", SSJson);
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       .abolish(submit_reposition_count(TaskName, _));
       !finalize_task(TaskName);
       action("skip").

// --- SUBMIT RESULT: falha → verificar alinhamento antes de rotacionar ---

// #52: bloco já alinhado e submit falhou ≥2x → não é problema de rotação
// (causa provavel: task expirada, goal zone errada, ou task já submetida por outro agente)
+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(failed)
      & block_already_aligned(TaskName)
      & submit_rotate_count(TaskName, RC) & RC >= 1
    <- .findall(att(AX,AY), attached(AX,AY), AttList);
       .findall(treq(RX,RY,RT), task_req(TaskName, RX, RY, RT), ReqList);
       .print("[SUBMIT] Step ", N, ": submit(", TaskName, ") falhou com bloco alinhado ", AttList, " == ", ReqList, ". Causa nao-rotacional. Finalizando.");
       .concat("{\"task\":\"", TaskName, "\",\"result\":\"failed_aligned\"}", SFJson);
       !dash_log("submit_fail", SFJson);
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       .abolish(submit_reposition_count(TaskName, _));
       !finalize_task(TaskName);
       action("skip").

// #52: bloco alinhado, primeira falha → re-tentar 1x sem rotacionar
+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(failed)
      & block_already_aligned(TaskName)
    <- .print("[SUBMIT] Step ", N, ": submit(", TaskName, ") falhou com bloco alinhado — re-tentando sem rotação.");
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       +submit_rotate_count(TaskName, 1);
       +pending_submit(TaskName);
       action("skip").

// --- SUBMIT RESULT: falha → rotacionar e re-tentar (até 4x, bloco NÃO alinhado) ---

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(failed)
      & submit_rotate_count(TaskName, RC) & RC < 4
    <- NewRC = RC + 1;
       .print("[SUBMIT] Step ", N, ": Submit FALHOU (rotacao ", NewRC, "/4). Rotacionando cw.");
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       +submit_rotate_count(TaskName, NewRC);
       +pending_submit(TaskName);
       action("rotate(cw)").

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(failed)
      & not submit_reposition_count(TaskName, _)
    <- .print("[SUBMIT] Step ", N, ": Submit FALHOU apos 4 rotacoes. Reposicionando (1/3).");
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       +submit_reposition_count(TaskName, 1);
       +pending_submit(TaskName);
       action("move(n)").

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(failed)
      & submit_reposition_count(TaskName, RPC) & RPC < 3
    <- NewRPC = RPC + 1;
       .print("[SUBMIT] Step ", N, ": Submit FALHOU apos 4 rotacoes. Reposicionando (", NewRPC, "/3).");
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       .abolish(submit_reposition_count(TaskName, _));
       +submit_reposition_count(TaskName, NewRPC);
       +pending_submit(TaskName);
       if ((NewRPC mod 3) == 1) { action("move(e)") }
       elif ((NewRPC mod 3) == 2) { action("move(s)") }
       else { action("move(w)") }.

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(failed)
    <- .print("[SUBMIT] Step ", N, ": Submit FALHOU apos todas tentativas. Desistindo.");
       .concat("{\"task\":\"", TaskName, "\",\"result\":\"failed\"}", SFJson);
       !dash_log("submit_fail", SFJson);
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       .abolish(submit_reposition_count(TaskName, _));
       !finalize_task(TaskName);
       action("skip").

// --- SUBMIT RESULT: qualquer outro falha (target, status, etc) ---

+step(N)
    : submitted_task(TaskName) & lastAction(submit) & lastActionResult(R) & R \== success
    <- .print("[SUBMIT] Step ", N, ": Submit falhou com ", R, ". Task ", TaskName, " provavelmente expirou.");
       -submitted_task(TaskName);
       .abolish(submit_rotate_count(TaskName, _));
       !finalize_task(TaskName);
       action("skip").

// --- pending_submit: timeout — desistir apos muitos steps ---

+step(N)
    : pending_submit(TaskName) & task_accepted_step(TaskName, AccStep) & (N - AccStep > 250)
    <- .print("[SUBMIT] Timeout: task ", TaskName, " apos ", N - AccStep, " steps. Desistindo.");
       .abolish(nav_block_count(_));
       !finalize_task(TaskName);
       action("skip").

// --- pending_submit: task expirou (via my_task_deadline ou known_task) ---

+step(N)
    : pending_submit(TaskName) & my_task_deadline(TaskName, Deadline) & N >= Deadline
    <- .print("[SUBMIT] Task ", TaskName, " expirou (deadline=", Deadline, "). Finalizando.");
       .abolish(nav_block_count(_));
       !finalize_task(TaskName);
       action("skip").

+step(N)
    : pending_submit(TaskName) & known_task(TaskName, Deadline, _, _) & N >= Deadline
    <- .print("[SUBMIT] Task ", TaskName, " expirou (deadline=", Deadline, "). Finalizando.");
       .abolish(nav_block_count(_));
       !finalize_task(TaskName);
       action("skip").

// --- pending_submit: VISIBLE goal zone nearby → navigate directly ---

+step(N)
    : pending_submit(TaskName) & my_pos(MX, MY) & not goalZone(0, 0) & not submitted_task(_)
      & goalZone(VGX, VGY) & (VGX \== 0 | VGY \== 0)
      & not last_move_blocked
    <- .abolish(has_destination(_, _));
       +has_destination(MX + VGX, MY + VGY);
       if (math.abs(VGX) >= math.abs(VGY)) {
           if (VGX > 0) { Dir = e } else { Dir = w }
       } else {
           if (VGY > 0) { Dir = s } else { Dir = n }
       };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act); action(Act).

// --- pending_submit: blocked → rotate, alt direction, or switch goal zone ---

+step(N)
    : pending_submit(TaskName) & my_pos(MX, MY) & not goalZone(0, 0) & not submitted_task(_)
      & (last_move_blocked | escape_pending(_, _)) & attached(_, _)
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       if (nav_block_count(OldC)) { -nav_block_count(OldC); BC = OldC + 1 }
       else { BC = 1 };
       +nav_block_count(BC);
       Mod3 = BC mod 3;
       if (BC >= 6) {
           .abolish(nav_block_count(_));
           +nav_block_count(0);
           .abolish(has_destination(_, _));
           get_alternative_goal_zone(MX, MY, MX, MY, AGX, AGY);
           if (AGX \== -1) {
               +has_destination(AGX, AGY);
               .print("[SUBMIT] Switch goal zone to (", AGX, ",", AGY, ") after ", BC, " blocks")
           };
           action("rotate(cw)")
       } elif (Mod3 == 0 & BC > 0) {
           action("rotate(cw)")
       } else {
           if (has_destination(DGX, DGY)) {
               !escape_move(MX, MY, DGX, DGY)
           } else {
               action("skip")
           }
       }.

+step(N)
    : pending_submit(TaskName) & my_pos(MX, MY) & not goalZone(0, 0) & not submitted_task(_) & last_move_blocked
    <- -last_move_blocked;
       .random(R);
       if (R < 0.25) { Dir = n }
       elif (R < 0.5) { Dir = e }
       elif (R < 0.75) { Dir = s }
       else { Dir = w };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act); action(Act).

// --- pending_submit: navigate to nearest goal zone (recalc every 15 steps) ---

+step(N)
    : pending_submit(TaskName) & my_pos(MX, MY) & not goalZone(0, 0) & not submitted_task(_)
      & has_destination(DX, DY)
    <- if ((N mod 15) == 0) {
           get_nearest_goal_zone(MX, MY, NGX, NGY);
           if (NGX \== -1) {
               .abolish(has_destination(_, _));
               +has_destination(NGX, NGY);
               compute_next_move(MX, MY, NGX, NGY, Dir);
               .abolish(last_attempted_dir(_));
               +last_attempted_dir(Dir);
               .concat("move(", Dir, ")", Act); action(Act)
           } else {
               compute_next_move(MX, MY, DX, DY, Dir);
               .abolish(last_attempted_dir(_));
               +last_attempted_dir(Dir);
               .concat("move(", Dir, ")", Act); action(Act)
           }
       } else {
           compute_next_move(MX, MY, DX, DY, Dir);
           if (Dir == "skip") {
               get_nearest_goal_zone(MX, MY, GX, GY);
               if (GX \== -1) {
                   .abolish(has_destination(_, _));
                   +has_destination(GX, GY);
                   compute_next_move(MX, MY, GX, GY, Dir2);
                   .abolish(last_attempted_dir(_));
                   +last_attempted_dir(Dir2);
                   .concat("move(", Dir2, ")", Act); action(Act)
               } else { action("skip") }
           } else {
               .abolish(last_attempted_dir(_));
               +last_attempted_dir(Dir);
               .concat("move(", Dir, ")", Act); action(Act)
           }
       }.

+step(N)
    : pending_submit(TaskName) & my_pos(MX, MY) & not goalZone(0, 0) & not submitted_task(_)
    <- get_nearest_goal_zone(MX, MY, GX, GY);
       if (GX \== -1) {
           .abolish(has_destination(_, _));
           +has_destination(GX, GY);
           compute_next_move(MX, MY, GX, GY, Dir);
           .abolish(last_attempted_dir(_));
           +last_attempted_dir(Dir);
           .concat("move(", Dir, ")", Act); action(Act)
       } else { action("skip") }.

// --- CONNECT RESULT: assembler (sucesso) → ir a goal zone ---

+step(N)
    : waiting_connect_result(Partner, TaskName) & lastActionResult(success) & my_pos(MX, MY)
    <- -waiting_connect_result(Partner, TaskName);
       .print("[CONNECT] Step ", N, ": Connect com ", Partner, " sucesso!");
       .concat("{\"task\":\"", TaskName, "\",\"partner\":\"", Partner, "\",\"result\":\"success\"}", CSJson);
       !dash_log("connect_success", CSJson);
       get_nearest_goal_zone(MX, MY, GX, GY);
       if (GX \== -1) {
           .abolish(has_destination(_, _));
           +has_destination(GX, GY);
           +pending_submit(TaskName);
           .print("[CONNECT] Indo para goal zone (", GX, ",", GY, ") para submit ", TaskName)
       };
       action("skip").

// --- CONNECT RESULT: assembler (falha) → retentar ---

+step(N)
    : waiting_connect_result(Partner, TaskName) & lastActionResult(R) & my_pos(MX, MY)
    <- -waiting_connect_result(Partner, TaskName);
       .print("[CONNECT] Step ", N, ": Connect falhou: ", R, ". Retentando.");
       .concat("{\"task\":\"", TaskName, "\",\"partner\":\"", Partner, "\",\"result\":\"fail\"}", CFJson);
       !dash_log("connect_fail", CFJson);
       +ready_to_connect(Partner, MX, MY, TaskName).

// --- CONNECT RESULT: collector (sucesso) ---

+step(N)
    : waiting_connect_collector(AsmName) & lastActionResult(success) & my_pos(MX, MY)
    <- -waiting_connect_collector(AsmName);
       .abolish(pending_connect_backup(_, _, _, _));
       .print("[CONNECT] Step ", N, ": Bloco transferido ao assembler com sucesso!");
       !do_explore(MX, MY).

// --- CONNECT RESULT: collector (falha) → retentar ---

+step(N)
    : waiting_connect_collector(AsmName) & lastActionResult(R)
      & pending_connect_backup(AsmName, AX, AY, TS)
    <- -waiting_connect_collector(AsmName);
       -pending_connect_backup(AsmName, AX, AY, TS);
       .print("[CONNECT] Step ", N, ": Connect falhou: ", R, ". Retentando.");
       +pending_connect(AsmName, AX, AY, TS).

// --- ASSEMBLER: chegou ao meeting point, iniciar connect ---

+step(N)
    : navigating_to_meeting_for_connect(SquadId, _, TaskName)
      & my_pos(MX, MY) & not has_destination(_, _)
    <- -navigating_to_meeting_for_connect(SquadId, _, TaskName);
       .print("[ASSEMBLER] Step ", N, ": No meeting point para task ", TaskName);
       get_squad_collectors(SquadId, Col1, Col2);
       !dash_task_phase(TaskName, "connect", 0);
       TargetStep = N + 5;
       if (Col1 \== "none") {
           !request_connect(Col1, TargetStep);
           +ready_to_connect(Col1, MX, MY, TaskName);
           .print("[ASSEMBLER] Solicitando connect com ", Col1)
       };
       action("skip").

// --- TRY CONNECT: assembler — detectar entidade adjacente via thing ---

+step(N)
    : ready_to_connect(Partner, PX, PY, TaskName) & my_pos(MX, MY)
      & attached(AX, AY)
      & thing(TX, TY, entity, _)
      & ((TX == 1 & TY == 0) | (TX == -1 & TY == 0) | (TX == 0 & TY == 1) | (TX == 0 & TY == -1))
    <- .concat("connect(", Partner, ",", AX, ",", AY, ")", Act);
       action(Act);
       -ready_to_connect(Partner, _, _, _);
       +waiting_connect_result(Partner, TaskName);
       .print("[CONNECT] Step ", N, ": Assembler connect(", Partner, ",", AX, ",", AY, ") partner at (", TX, ",", TY, ")").

// --- TRY CONNECT: assembler — sem entidade adjacente, esperar ---

+step(N)
    : ready_to_connect(_, _, _, _) & my_pos(MX, MY)
    <- action("skip").

// --- TRY CONNECT: collector — navegar ou connect ---

+step(N)
    : pending_connect(AsmName, AsmX, AsmY, TS) & my_pos(MX, MY) & attached(AX, AY)
      & thing(TX, TY, entity, _)
      & ((TX == 1 & TY == 0) | (TX == -1 & TY == 0) | (TX == 0 & TY == 1) | (TX == 0 & TY == -1))
    <- .concat("connect(", AsmName, ",", AX, ",", AY, ")", Act);
       action(Act);
       -pending_connect(AsmName, _, _, _);
       +pending_connect_backup(AsmName, AsmX, AsmY, TS);
       +waiting_connect_collector(AsmName);
       .print("[CONNECT] Step ", N, ": Collector connect(", AsmName, ",", AX, ",", AY, ")").

// U9: AsmX,AsmY agora sao traduzidos para o frame do collector no
// momento da recepcao (communication.asl) via known_offset.
+step(N)
    : pending_connect(AsmName, AsmX, AsmY, TS) & my_pos(MX, MY)
    <- CDX = AsmX - MX; CDY = AsmY - MY;
       if (CDX > 0 & (CDX >= CDY | CDX >= -CDY)) { MoveDir = e }
       elif (CDX < 0 & (-CDX >= CDY | -CDX >= -CDY)) { MoveDir = w }
       elif (CDY > 0) { MoveDir = s }
       else { MoveDir = n };
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(MoveDir);
       .concat("move(", MoveDir, ")", Act);
       action(Act).
