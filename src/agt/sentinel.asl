// ============================================================
// sentinel.asl — Agente Sentinel (soloist híbrido)
// ------------------------------------------------------------
// O sentinel não pertence a um squad fixo: opera como soloist
// autônomo do pool universal. Coleta e submete tarefas de 1 bloco
// por conta própria (via self-assign do connect_protocol) e também
// aceita soloist_task delegadas por um líder. Toda a lógica comum
// (percepção, navegação, coleta, connect, adoção de papel) vem dos
// módulos incluídos abaixo; aqui ficam apenas os planos específicos.
// ============================================================

// Módulos comuns compartilhados por todos os papéis (ordem = prioridade):
{ include("common/perception.asl") }       // traduz percepções em crenças
{ include("common/shared_map_init.asl") }  // cria/foca o SharedMap
{ include("$jacamo/templates/common-cartago.asl") }
{ include("$jacamo/templates/common-moise.asl") }
{ include("common/organization.asl") }     // adesão à organização MOISE+
{ include("common/dashboard_hooks.asl") }  // telemetria opcional
{ include("common/map_merge.asl") }        // fusão de mapas (modo relativo)
{ include("common/role_adoption.asl") }    // adoção de 'worker' (cenário oficial)
{ include("common/connect_protocol.asl") } // submit, normas, connect, self-assign
{ include("common/collection.asl") }       // ciclo de coleta de blocos
{ include("common/navigation.asl") }       // A*/greedy + exploração

my_role_type(sentinel).

!start.

// Inicialização: cria/foca os artefatos compartilhados e abre a
// conexão EIS (EISAccess) com o servidor MASSim.
+!start
    <- .my_name(Me);
       .print("[SENTINEL] ", Me, " iniciado.");
       !setup_shared_map;
       !try_set_grid_dims;
       !setup_task_board;
       !setup_squad_coordinator;
       !setup_hive_dashboard;
       makeArtifact(Me, "connection.EISAccess", ["eismassimconfig.json", Me], EisId);
       focus(EisId);
       .print("[SENTINEL] Conectado. Modo: hibrido (soloist + patrulha).").

+!setup_task_board
    <- lookupArtifact("task_board", TbId); focus(TbId).
-!setup_task_board
    <- .wait(50); !try_create_task_board.
+!try_create_task_board
    <- makeArtifact("task_board", "env.TaskBoard", [], TbId); focus(TbId).
-!try_create_task_board
    <- .wait(100); !setup_task_board.

+!setup_squad_coordinator
    <- lookupArtifact("squad_coordinator", ScId); focus(ScId).
-!setup_squad_coordinator
    <- .wait(50); !try_create_squad_coordinator.
+!try_create_squad_coordinator
    <- makeArtifact("squad_coordinator", "env.SquadCoordinator", [], ScId); focus(ScId).
-!try_create_squad_coordinator
    <- .wait(100); !setup_squad_coordinator.

+name(N)  <- .print("[SENTINEL] SIM-START: nome = ", N).
+team(T)  <- -my_team(_); +my_team(T); .print("[SENTINEL] SIM-START: time = ", T).
+steps(S) <- .print("[SENTINEL] SIM-START: steps = ", S).

// --- SOLOIST TASK: delegada por um líder via pool ---
// Se estiver livre, assume a tarefa: marca-se ocupado, limpa qualquer
// estado anterior e inicia a coleta do bloco (ou limpa blocos presos
// antes, se já houver algo acoplado).

+soloist_task(TaskName, BlockType, Deadline)[source(S)]
    : not my_active_task(_, _) & step(CurStep)
    <- .print("[SENTINEL] Soloist task ", TaskName, ": coletar ", BlockType, " deadline=", Deadline);
       .my_name(Me);
       mark_busy(Me);
       .abolish(collecting(_, _, _));
       .abolish(has_destination(_, _));
       .abolish(waiting_request(_, _));
       .abolish(waiting_attach_result(_, _));
       .abolish(collected_block(_));
       .abolish(solo_mode(_));
       .abolish(solo_block_type(_));
       .abolish(request_retries(_, _));
       .abolish(task_accepted_step(_, _));
       .abolish(my_task_deadline(_, _));
       .abolish(searching_dispenser(_));
       .abolish(needs_clear_blocks(_));
       +my_task_deadline(TaskName, Deadline);
       +my_active_task(TaskName, "solo");
       +solo_mode(TaskName);
       +solo_block_type(BlockType);
       +task_accepted_step(TaskName, CurStep);
       if (attached(_, _)) {
           +needs_clear_blocks(BlockType)
       } else {
           !collect_block(BlockType)
       }.

+soloist_task(TaskName, BlockType, Deadline)[source(S)]
    <- .print("[SENTINEL] Rejeitando soloist_task ", TaskName, " (ocupado)").

// --- SOLO: bloco coletado → ir a goal zone para submit ---

+collected_block(Type)
    : solo_mode(TaskName) & my_role_type(sentinel) & my_pos(MX, MY)
    <- .print("[SENTINEL] Bloco ", Type, " coletado para submit ", TaskName);
       !dash_task_phase(TaskName, "submit_nav", 50);
       +pending_submit(TaskName);
       get_nearest_goal_zone(MX, MY, GX, GY);
       if (GX \== -1) {
           .abolish(has_destination(_, _));
           +has_destination(GX, GY);
           .print("[SENTINEL] Nav goal zone (", GX, ",", GY, ") para submit ", TaskName)
       } else {
           .print("[SENTINEL] Nenhuma goal zone conhecida. pending_submit ativo.")
       }.

// --- Finalizar task e voltar ao pool ---
// Libera o agente (mark_free), conclui a tarefa no TaskBoard e zera
// todas as crenças de estado para um próximo ciclo limpo.

+!finalize_task(TaskName)
    <- .my_name(Me);
       mark_free(Me);
       complete_task(TaskName);
       release_agent_from_task(TaskName, Me);
       .abolish(my_active_task(_, _));
       .abolish(pending_submit(_));
       .abolish(submitted_task(_));
       .abolish(submit_rotate_count(_, _));
       .abolish(submit_reposition_count(_, _));
       .abolish(task_accepted_step(_, _));
       .abolish(solo_mode(_));
       .abolish(solo_block_type(_));
       .abolish(solo_blocks_needed(_));
       .abolish(solo_blocks_collected(_));
       .abolish(my_task_deadline(_, _));
       .abolish(collecting(_, _, _));
       .abolish(has_destination(_, _));
       .abolish(nav_block_count(_));
       .abolish(searching_dispenser(_));
       .abolish(needs_clear_blocks(_));
       .abolish(collect_nav_start(_));
       .abolish(solo_saved_req(_, _, _));
       .abolish(partner_role(_, _));
       .abolish(partner_target_pos(_, _, _, _));
       .abolish(partner_connect_target(_, _));
       .abolish(partner_block_collected(_));
       .abolish(partner_signaled_ready);
       .abolish(awaiting_partner(_, _, _, _, _, _));
       .abolish(confirmed_partner(_, _));
       .abolish(do_connect_with_partner(_, _));
       .abolish(collected_block(_));
       .abolish(waiting_request(_, _));
       .abolish(waiting_attach_result(_, _));
       .abolish(request_retries(_, _));
       .concat("{\"task\":\"", TaskName, "\"}", FJson);
       !dash_log("task_finalized", FJson);
       !dash_task_phase(TaskName, "done", 100);
       .print("[SENTINEL] Task ", TaskName, " finalizada. Voltando a patrulha.").

-!finalize_task(_) <- true.

// --- Limpar task expirada ---

+!check_expired_task
    : my_active_task(TaskName, _) & step(N) & known_task(TaskName, Deadline, _, _) & N >= Deadline
    <- .print("[SENTINEL] Task ", TaskName, " expirou! Limpando...");
       !finalize_task(TaskName).

+!check_expired_task
    : my_active_task(TaskName, _) & step(N)
      & task_accepted_step(TaskName, AccStep) & (N - AccStep > 300)
    <- .print("[SENTINEL] Task ", TaskName, " timeout (", N - AccStep, " steps). Limpando...");
       !finalize_task(TaskName).

+!check_expired_task <- true.
-!check_expired_task <- true.
