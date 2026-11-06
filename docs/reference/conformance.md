# Conformance — requirement to guard

Every requirement this tree claims, and the test that asserts it. The rule the design series sets for
itself applies here first: **a claim with no generator behind it is a defect.** A requirement with no
named test below is not claimed, however much of it happens to be implemented.

Requirement identifiers are from
01 — High-level specification §5.
Of the 255 distinct requirement identifiers defined in the design series' requirement tables, **252 are
asserted here.** The rest are listed as not claimed where their family appears below, or belong to
subsystems this tree does not yet contain. The count is every `| X-NN |` row across documents 01 to 11,
de-duplicated; an earlier version of this page said 266, which counted some identifiers twice.

## Control (C) — 8 of 8

| ID | Requirement | Guard |
|---|---|---|
| C-01 | Every entry passes the door; nothing runs without a context | `construct_a_context.rs` (compile-fail) · `every_admitted_entry_closes_exactly_one_span` · `the_command_line_clears_the_same_checks_as_a_request_from_outside` |
| C-02 | A context is the only source of a scoped handle | `an_entry_adapter_cannot_name_a_store_engine_or_the_secret_boundary` · `the_other_entry_adapters_cannot_name_an_engine` |
| C-03 | Write needs editor; a confirmed write needs the token | `execute_on_a_read_context.rs` · `admit_directly_as_confirmed.rs` · `declare_a_fourth_mode.rs` (compile-fail) · `a_viewer_may_read_but_a_write_needs_a_higher_tier` · `cancelling_needs_a_confirmation_and_the_confirmation_is_spent_once` · `a_confirmation_issued_to_one_person_does_not_work_for_another` |
| C-04 | Identity derived once, issuer included | `an_unknown_credential_is_refused_as_no_identity_rather_than_as_a_server_error` · `a_link_on_one_channel_is_not_a_link_on_another` |
| C-05 | A secret reference is neither serializable nor loggable | `serialize_a_secret.rs` (compile-fail) · `debug_names_nothing_that_could_identify_the_material` · `a_result_cannot_carry_material_out_even_when_the_remote_system_echoes_it` · `a_token_never_prints_itself` |
| C-06 | Budgets checked from the single ledger | `a_spend_that_reaches_the_ceiling_passes_and_one_that_crosses_it_refuses` · `the_door_refuses_an_entry_whose_budget_is_already_spent` · `a_completed_turn_is_metered_into_the_one_ledger` |
| C-07 | Every refusal carries a code and is recorded | `every_code_names_itself_and_maps_to_one_status` · `a_refusal_is_recorded_with_its_code_and_opens_no_span` |
| C-08 | Root is a database invariant, at most one | `inserting_the_same_identifier_twice_collides_which_is_how_an_invariant_holds` · `root_holds_admin_over_a_package_no_row_mentions` |

## Packages (P) — 8 of 8

| ID | Requirement | Guard |
|---|---|---|
| P-01 | Everything declared; an undeclared capability is not linked | `a_capability_the_manifest_never_asked_for_cannot_be_granted` · `a_capability_the_manifest_never_asked_for_is_refused_at_the_host` · `a_node_package_is_refused_a_capability_its_manifest_never_asked_for` · `a_declared_route_with_nothing_behind_it_fails_at_load` |
| P-02 | Install, upgrade, deactivate and unload without a restart | `a_package_reaches_active_by_passing_every_gate_in_order` · `an_upgrade_brings_the_new_version_up_while_the_old_one_drains` · `a_serving_package_cannot_be_unloaded_from_under_its_callers` · `a_package_that_is_not_active_answers_nothing` · `a_drained_node_package_stops_answering_and_its_process_goes_away` |
| P-03 | A package compiles only against the versioned SDK; range mismatch refused | `what_a_package_compiles_against_names_no_kernel_crate` · `a_kernel_outside_the_declared_range_refuses_at_install_rather_than_in_production` · `a_caret_range_accepts_additions_and_refuses_the_next_breaking_version` |
| P-04 | Migrations run in the package's namespace; a failure leaves it inactive | `a_failed_migration_leaves_the_package_where_it_was_and_never_serving` · `a_migration_that_cannot_be_undone_is_named_before_it_is_run` |
| P-05 | Sandbox tests run before activation with verdict integrity | `a_package_that_declared_no_tests_has_proven_nothing` · `a_declined_run_is_not_a_pass` · `truncated_evidence_cannot_flip_a_verdict_in_either_direction` · `a_run_that_stopped_early_is_pending_rather_than_passing_on_what_it_managed` · `only_a_complete_clean_run_passes` · `a_package_that_declared_no_tests_cannot_pass_the_sandbox_or_move_on` |
| P-06 | A group carries no code | `a_group_that_carries_code_is_refused` · `a_group_that_carries_code_is_refused_at_validation_and_does_not_run` |
| P-07 | Status renders without the kernel knowing the schema | `the_kernel_renders_a_shape_it_has_never_seen` · `a_different_package_with_a_different_shape_needs_no_kernel_change` · `a_package_that_reports_nothing_still_renders` · `a_status_route_cannot_leak_a_credential_through_the_cockpit` |
| P-08 | A registry is a trusted row; packages install only from one | `a_package_installs_only_from_a_row_somebody_trusted` · `a_package_installs_only_from_a_registry_row_somebody_trusted` · `withdrawing_trust_takes_effect_without_losing_the_row` · `an_unknown_registry_is_not_found_rather_than_quietly_allowed` |

The lifecycle itself is a state machine, so a move that skips a gate does not exist:
`the_lifecycle_has_no_move_that_skips_the_sandbox` · `the_lifecycle_has_no_shortcut_from_installed_to_serving`
· `anything_can_be_refused_and_nothing_comes_back_from_refusal`.

**Hosts.** Spec §4.5 says the host interface is language-neutral and that two hosts satisfy it, without
giving that a requirement identifier, so it is asserted here without inventing one:
`a_call_reaches_package_code_compiled_into_this_binary` ·
`a_call_reaches_package_code_running_under_node` ·
`a_sandboxed_package_goes_through_the_same_lifecycle_as_every_other_kind` ·
`every_host_this_artifact_has_satisfies_the_same_interface` ·
`what_a_package_writes_lands_in_its_own_namespace_and_nowhere_else`. Three hosts are put through the
same assertions, and two of them are real: a child `node` process, and a WebAssembly module in a
sandbox. What makes the sandbox one is asserted separately:
`a_sandboxed_package_reaches_the_kernel_only_through_what_it_was_linked` ·
`a_module_asking_for_an_import_nobody_offers_does_not_run_at_all` ·
`a_module_that_loops_forever_is_stopped_instead_of_taking_a_thread_with_it` ·
`a_refusal_reaches_the_module_as_a_value_it_has_to_handle`.

**Surfaces.** A package's static files are served only while it is active, and only to an admitted
caller: `an_active_package_serves_its_surface_and_stops_when_it_is_deactivated` ·
`a_surface_needs_a_credential_like_everything_else_behind_the_door` ·
`a_path_that_tries_to_climb_out_finds_nothing` ·
`the_inventory_lists_what_is_actually_serving_a_surface`.

## Bots and swarm (B) — 11 of 13, and B-17..B-22 from the amendments

| ID | Requirement | Guard |
|---|---|---|
| B-01 | Every bot invocation clears one admission decision regardless of transport | `the_same_refusal_set_applies_on_every_transport` (HTTP, stream, package call, schedule tick and command line) |
| B-02 | The brain resolves from layered records, no literal | `the_most_specific_rung_wins_however_the_records_arrive` · `a_bot_default_outranks_the_fleet_and_the_registry` · `no_record_resolves_to_nothing_rather_than_to_a_literal` · `a_bot_with_no_resolvable_brain_refuses_rather_than_picking_a_model` · `a_caller_supplied_brain_is_used_for_that_turn_and_changes_nothing_after_it` |
| B-03 | A bot never receives credentials or raw connector payloads | `a_credential_cannot_be_put_in_front_of_a_model` · `persona_text_is_data_and_is_scrubbed_like_everything_else` · `a_provider_cannot_reach_a_credential` |
| B-04 | Providers behind one trait; a `noop` provider exists | `a_completed_turn_is_metered_into_the_one_ledger` (against a named provider) · `NoopProvider` is exported for isolation |
| B-05 | The kernel does not spawn a harness | `no_kernel_crate_can_start_a_process` · `the_crate_list_this_guard_checks_is_every_crate_except_the_agent_and_the_artifact` |
| B-06 | One envelope, identical semantics on every transport | `in_process_delivery_satisfies_the_contract` · `durable_delivery_satisfies_the_same_contract` · `remote_node_delivery_satisfies_the_same_contract` · `durable_delivery_differs_in_the_one_way_it_is_meant_to` · `in_process_delivery_keeps_nothing_across_a_restart_and_does_not_pretend_to` |
| B-07 | A ticket type without a loaded workflow waits, never guesses | `a_ticket_type_with_no_loaded_workflow_waits_rather_than_running_something_else` · `a_phase_naming_a_bot_nobody_registered_refuses_rather_than_finding_another` |
| B-09 | A harness joins only as an enrolled node, local or remote alike | `a_token_nobody_enrolled_is_refused` · `a_node_cannot_be_bound_to_a_bot_its_owner_does_not_hold` · `a_node_cannot_claim_for_a_bot_it_was_never_bound_to` · `a_local_harness_enrols_exactly_like_a_remote_one` |
| B-10 | A generation is pinned at claim; a change mid-run fails the run | `a_node_that_has_reported_nothing_cannot_pin_a_run_to_anything` · `completing_under_a_different_configuration_abandons_the_run_and_never_retries_it` · `a_harness_reconfigured_mid_run_abandons_the_run_instead_of_reporting_it_done` · `a_changed_generation_is_not_retried` |
| B-11 | No envelope carries a credential; phase scopes travel with it | `an_envelope_carries_the_phase_scopes_and_not_a_wider_set` · `a_bound_node_claims_runs_and_completes_under_the_configuration_it_pinned`; the `Envelope` type has no secret field and `oshal-node` has no vault |
| B-12 | Reported cost is never summed with metered cost | `reported_cost_never_joins_the_number_a_budget_enforces` · `what_a_node_reports_is_recorded_and_never_joins_what_the_kernel_metered` · `a_claimed_envelope_is_run_and_completed_with_what_it_cost_its_owner` |
| B-08 | External agents join only through a default-off gateway with per-agent scoped credentials | the Y-01 and Y-02 guards below: `a_gateway_nobody_turned_on_says_there_is_nothing_here` · `an_enrolled_agent_is_admitted_by_its_own_credential_once_the_gateway_is_on` · `a_credential_cannot_be_used_to_call_as_a_different_agent` |
| B-17 | The authorizing record names provider and model, and a result from a different one is not success | `an_answer_from_a_model_nobody_authorized_is_not_accepted_and_its_cost_is_still_metered` |
| B-18 | Tool authorization is automatic, ask or off; ask requests approval mid-turn and a timeout denies | `an_off_tool_is_not_offered_to_the_model_at_all` · `an_automatic_tool_runs_without_asking` · `an_ask_tool_waits_mid_turn_for_a_person_and_runs_when_they_approve` · `an_ask_tool_nobody_answers_is_denied_when_the_wait_runs_out` · `an_ask_tool_the_person_declines_does_not_run` |
| B-19 | A package declares an inference hint, never an endpoint, model or key | `BotDecl` has a `hint` and refuses unknown fields · `a_bot_declaration_that_binds_a_model_does_not_parse` · `a_packages_hint_resolves_to_the_brain_the_installation_mapped_it_to` · `a_hint_nobody_mapped_falls_through_to_the_fleet_rather_than_to_a_guess` |
| B-20 | A call's key resolves caller-first, then tenant, then a capped operator pool, else refuses; the ledger records which paid | `the_key_that_pays_is_the_callers_then_the_tenants_then_a_capped_pool_and_the_ledger_says_which` |
| B-21 | What ran matches what was authorized; a failover onto an unauthorized brain is refused after the fact | `an_answer_from_a_model_nobody_authorized_is_not_accepted_and_its_cost_is_still_metered` (the spend is metered, the answer is not accepted) |
| B-22 | Created, provisioned and operational are distinct states reported truthfully; a bot with unbound tools is not described as deployed | `a_registered_bot_is_not_described_as_running_until_it_is` |

A node-run phase is claimed by a machine holding a device token (B-09); the envelope it carries was
dispatched from an admitted context, so the decision was made at the door before the work left it.
B-13 to B-16 are below. For B-17 the authorizing record is the brain the scoped call resolved before it asked, and for
a node-run phase it is the generation pinned at claim (B-10). An installation whose providers take no
per-call key declares no payment table and records no payer; one that declares a table resolves a key
for every call.

## Tenancy and users (T) — 5 of 5, and T-06 and T-09 from the amendments

| ID | Requirement | Guard |
|---|---|---|
| T-01 | Every keyed name derives from (subject, tenant) through one function | `two_people_in_one_tenant_share_the_tenant_key_and_not_the_person_key` · `one_subject_in_two_tenants_never_shares_a_key` · `the_key_is_opaque_and_leaks_neither_subject_nor_tenant` |
| T-02 | Relational isolation is row-level security under a governed least-privilege role converged from one contract | against a real server: `a_row_written_under_one_scope_is_invisible_under_another` · `a_session_that_set_no_scope_key_sees_nothing_at_all` · `the_governed_role_cannot_turn_the_policy_off` · `the_roles_hold_exactly_what_the_contract_grants_them_after_boot` · `converging_twice_leaves_the_same_grants_rather_than_accumulating_them` · `a_reader_role_cannot_write_even_though_it_can_see_its_own_rows` · `one_subject_in_two_tenants_sees_two_different_sets_of_rows`; and in memory: `a_document_written_under_one_scope_does_not_exist_under_another` · `a_person_in_another_tenant_does_not_see_these_tickets` |
| T-03 | One tier vocabulary; explicit deny wins | `deny_outranks_every_other_tier_however_the_set_is_ordered` · `deny_satisfies_nothing_including_itself` · `an_empty_grant_set_is_no_opinion_rather_than_permission` · `a_deny_row_decides_the_package_however_many_admin_rows_accompany_it` · `an_explicit_deny_outranks_the_editor_tier_the_same_principal_holds` |
| T-04 | A declared schedule alone runs nothing | `a_declared_schedule_that_nobody_activated_refuses_its_tick` · `activation_names_the_principal_the_tick_runs_as` · `a_schedule_no_package_declares_cannot_be_activated_into_existence` |
| T-05 | Guest access is a seeded principal with a declared capability matrix | `a_guest_is_a_seeded_principal_holding_exactly_its_declared_matrix` · `with_no_guest_declared_a_caller_who_presents_nothing_is_nobody` |
| T-06 | A worker principal gets a narrower database role that can execute only enumerated helpers answering one question about one row, never the tables; the helper set re-converges every boot | `a_worker_can_call_its_helpers_and_cannot_read_the_table` (against PostgreSQL, including that the callable set equals `store::WORKER_HELPERS`) · `the_helper_set_converges_again_at_every_boot` |
| T-09 | A run-time authorization denial suspends the activation with the decision's reason | `a_schedule_whose_principal_lost_the_right_is_suspended_with_the_reason` |

**T-02 is now asserted against a database.** The PostgreSQL engine enforces isolation with row-level
security under a governed `NOBYPASSRLS` role, and the tests step outside the engine to prove the
database is what refuses: an unscoped session sees nothing, and the governed role cannot switch the
policy off. The in-memory engine files documents under the scope key for the same effect without a
server. A guest exists only when a matrix is declared, and a matrix may grant viewing or deny and nothing more.

## Observability (O) — 5 of 5

| ID | Requirement | Guard |
|---|---|---|
| O-01 | One span per admitted entry, emitted by the door | `an_admitted_entry_produces_exactly_one_span_record` · `every_admitted_entry_closes_exactly_one_span` · `a_linked_address_is_admitted_as_the_person_it_belongs_to` |
| O-02 | One ledger feeds budgets and totals | `reported_cost_never_joins_the_number_a_budget_enforces`; `Budget.spent` is read from `Ledger::totals_for_actor` at the door |
| O-03 | Inventories are generated, not typed | `every_route_in_the_inventory_resolves_so_the_inventory_is_not_a_list_someone_maintains` · `the_inventory_reports_what_is_loaded_rather_than_what_was_typed_into_a_document` |
| O-04 | Every sink passes the redaction test | `sealing_is_the_only_constructor_and_it_scrubs` · `a_field_named_as_a_credential_is_masked_whatever_its_value_looks_like` · `a_bare_token_is_masked_by_its_shape_alone` · `a_named_credential_field_loses_its_value_and_keeps_its_name` · `ordinary_prose_survives_untouched` · `detail_is_scrubbed_on_the_way_in_so_a_refusal_cannot_carry_a_credential` · `a_message_body_is_scrubbed_before_anything_reads_it` |
| O-05 | An unmeasured verdict axis is null, never zero, and an escalated-but-scored run reads as degraded | `an_axis_nobody_measured_is_stored_as_null_rather_than_zero` · `a_scorecard_with_an_unmeasured_axis_is_degraded_and_yields_no_quality` · `a_run_that_escalated_reads_as_degraded_however_well_it_scored` · `a_fully_measured_clean_run_passes_and_a_low_axis_fails` |

O-04 is discharged by the signature: a sink takes `Redacted<Record>`, and the only constructor of
`Redacted<T>` runs the scrubber. A new sink cannot skip it, because there is nothing else to accept.

## The task workspace (WS) and any-harness collaboration (HA)

| ID | Requirement | Guard |
|---|---|---|
| WS-01 | One workspace per ticket, archived with it | `a_workspace_belongs_to_its_ticket_and_is_archived_with_it` |
| WS-02 | Every commit carries its full provenance | `a_commit_missing_half_its_provenance_is_refused` |
| WS-03 | A write needs a claim; out-of-claim paths are refused and named | `a_commit_reaching_outside_its_claim_is_refused_with_those_paths_named` · `a_claim_cannot_be_used_by_a_bot_that_does_not_hold_it` · `a_scope_names_what_falls_outside_it_rather_than_dropping_it` |
| WS-04 | A stale base is refused unless the path declares a merge policy | `a_commit_on_a_stale_base_is_refused_when_somebody_else_touched_those_paths` · `a_stale_commit_is_reconciled_when_the_path_declares_a_policy_that_can` · `a_stale_base_is_fine_when_nobody_touched_the_same_paths` |
| WS-05 | Merge policies come from a closed vocabulary, declared per glob | `a_policy_outside_the_vocabulary_is_refused_where_it_is_declared` · `a_later_narrower_declaration_overrides_a_broader_one` · `exclusive_does_not_reconcile_a_stale_write_and_the_others_do` |
| WS-06 | A claim expires with its lease and releases on completion | `a_node_that_dies_holds_nothing_once_its_lease_lapses` · `a_claim_whose_lease_lapsed_stops_blocking_anyone` · `releasing_a_claim_frees_its_paths_immediately` |
| WS-07 | A commit matching a secret pattern is refused | `a_commit_carrying_credential_shaped_content_is_refused_and_names_the_file` |
| WS-08 | Artifacts are typed and discoverable by other bots on the task | `two_harnesses_finish_one_task_and_the_second_is_told_nothing_but_the_workspace` |
| WS-09 | Freeze gives a stable readable state while still assigned | `freezing_keeps_the_workspace_readable_and_stops_it_taking_writes` |
| WS-10 | A workspace is exportable and scoped | `an_export_is_the_whole_contents_and_a_deletion_removes_a_path` · `a_workspace_in_one_tenant_is_not_a_workspace_in_another` |
| WS-11 | An artifact handle is owner-bound, short-lived, audit-logged and carries no bytes; only its minter resolves it | `only_the_principal_who_minted_a_handle_resolves_it` · `a_handle_stops_resolving_when_it_expires` · `every_mint_and_resolution_is_logged_including_the_refusals` · `a_handle_holds_a_route_and_never_bytes` |
| WS-12 | A handle's source is a same-origin application route; local paths and absolute URLs are refused at mint | `local_paths_and_absolute_urls_are_refused_at_mint` |
| HA-01 | Two harness kinds complete consecutive phases on one workspace, each attributed | `two_harnesses_finish_one_task_and_the_second_is_told_nothing_but_the_workspace` (asserts `Workspace::attribution`) |
| HA-02 | Overlapping claims serialize; disjoint claims run at once | `two_bots_on_different_subtrees_both_get_their_claim` · `a_second_claim_on_the_same_paths_is_refused_and_says_who_holds_them` · `overlap_errs_towards_yes_when_a_wildcard_makes_it_uncertain` |
| HA-05 | An oversized or secret-bearing change set is refused | `a_change_set_larger_than_the_workspace_accepts_is_refused` and WS-07 above |
| HA-06 | Handover works through workspace state and typed artifacts alone | `two_harnesses_finish_one_task_and_the_second_is_told_nothing_but_the_workspace` |
| HA-03 | A harness that cannot emit a diff is supported by kernel-side diffing | `a_harness_that_cannot_emit_a_diff_hands_back_its_files_and_the_kernel_works_out_the_change` |
| HA-04 | A node declares harness capabilities and routing honours them | `routing_honours_what_each_harness_declared_it_can_do` |

## Assistant rails (AS) — 7 of 7

Requirement identifiers from
08 — The task workspace and the assistant §6.
The assistant is a package; these are the rails the kernel owes it.

| ID | Requirement | Guard |
|---|---|---|
| AS-01 | The capability catalog is grant-filtered per principal | `two_people_see_different_catalogs_and_what_one_may_not_use_is_absent` |
| AS-02 | Routing comes from declarations; a new capability needs no assistant change | `a_new_package_is_routable_by_its_manifest_alone_and_nothing_is_guessed` |
| AS-03 | The assistant acts as the person, never with elevated authority | `Installation::catalog` and `hand_off` take the person's context and read that principal's grants, with no parameter naming anyone else · `two_people_see_different_catalogs_and_what_one_may_not_use_is_absent` |
| AS-04 | A failure surfaces the real cause | `an_ambiguous_request_names_the_real_reason_rather_than_apologising` |
| AS-05 | A refused or failed request leaves no partially created task | `a_request_that_fails_halfway_leaves_no_task_behind` |
| AS-06 | Surfaces declare affordances the assistant can hand off to | `the_assistant_hands_a_person_to_the_surface_that_does_the_thing` · `an_affordance_must_hand_off_to_a_surface_the_package_serves` |
| AS-07 | Every surface remains usable with the assistant disabled | `every_surface_is_served_with_no_assistant_installed_at_all` — there is no assistant in the kernel to disable |

AS-05 is enforced by taking back what a request already wrote when a later step of it fails: the store
API has no multi-statement transaction, so a second failure during the take-back can still leave a row.
The failure that the test forces — the second write refused — leaves nothing.

## External agents (Y)

| ID | Requirement | Guard |
|---|---|---|
| Y-01 | The gateway and card are absent unless enabled; absent means not-found | `a_gateway_nobody_turned_on_says_there_is_nothing_here` · `turning_the_gateway_off_stops_admitting_without_forgetting_anybody` |
| Y-02 | Each agent has its own credential and scopes; revoking one affects nobody else | `an_enrolled_agent_is_admitted_by_its_own_credential_once_the_gateway_is_on` · `revoking_one_agent_leaves_every_other_agent_alone` · `a_credential_cannot_be_used_to_call_as_a_different_agent` |
| Y-03 | No confirmed context without an explicit, separate grant | `an_external_agent_cannot_reach_a_confirmed_context_until_that_is_granted` |
| Y-04 | Outbound calls are schema-bounded, budgeted and recorded | `an_outbound_call_is_budgeted_and_what_it_reports_never_joins_metered_cost` · `what_leaves_this_installation_is_scrubbed_before_it_goes` · `a_revoked_agent_is_not_called_even_by_a_caller_holding_an_older_record` |
| Y-05 | No protocol type reaches a kernel crate | `no_protocol_type_from_the_agent_gateway_reaches_a_kernel_crate` |

## Deployment (D) — 6 of 6

| ID | Requirement | Guard |
|---|---|---|
| D-01 | One artifact, nothing else installed | `cargo run -p oshald` serves with no external service; every end-to-end test runs against that same wiring |
| D-02 | Start is order-independent; an unreachable store is a health state | `an_unreachable_store_is_a_refusal_and_not_a_panic` · `an_unreachable_store_is_reported_as_a_health_state_and_the_process_keeps_serving` |
| D-03 | Upgrade is an artifact swap plus embedded migrations; rollback is the previous artifact | `an_upgrade_and_a_rollback_are_artifact_swaps_over_the_same_database` (against PostgreSQL) · `the_contract_only_ever_adds` |
| D-04 | Modes are declared postures; a mode name never invents behaviour outside its table | `Deployment::permits` is the one place a deployment becomes behaviour · `every_deployment_is_a_row_of_the_posture_table_and_stricter_rows_permit_no_more` · `an_enterprise_posture_has_no_guest_and_refuses_to_start_with_one` · `only_a_demo_may_use_a_mock_identity_source` |
| D-05 | Monitoring is inherited from package declarations, never registered by hand | `a_bot_a_package_declares_is_a_monitoring_target_until_the_package_goes` · `every_declared_bot_is_a_monitoring_target_without_a_configuration_edit` |
| D-06 | A deploy outcome distinguishes rolled-back-and-serving from nothing-serving; an unrecognised outcome fails closed | `rolled_back_and_serving_is_not_the_same_as_nothing_serving` · `an_outcome_this_kernel_does_not_recognise_fails_closed` |

The embedded contract is the migration: each artifact converges the database to its own contract at
boot, and because a contract only ever adds, the previous artifact runs against a database the next
one converged.

## Identity and sign-in (I) — 6 of 6

Requirement identifiers from
05 — Subsystem specifications §A.

| ID | Requirement | Guard |
|---|---|---|
| I-01 | `Principal` carries issuer and subject; no path keys on the subject alone | `two_issuers_minting_the_same_subject_are_two_different_people` · `providers::tests::the_same_subject_at_two_issuers_is_two_identities` · `the_same_subject_from_two_sources_resolves_to_two_different_people` |
| I-02 | Identity derived from verified claims once per entry, on every entry kind | one `IdentitySource`, asked once by the door: `a_token_from_the_configured_provider_passes_the_door_and_reaches_a_surface` · `a_suspended_person_is_refused_on_every_entry_kind` · `a_link_on_one_channel_is_not_a_link_on_another` |
| I-03 | Linking is explicit and auditable; an unlinked identity inherits nothing | `a_second_identity_reaches_an_existing_person_only_once_it_is_linked` · `unlinking_takes_the_second_identity_away_again` · `an_identity_already_linked_cannot_be_taken_over_by_linking_it_again` · `providers::tests::linking_and_unlinking_are_both_on_the_record` |
| I-04 | A provider row with auto-provision off refuses an unknown subject | `an_issuer_that_does_not_provision_refuses_somebody_nobody_linked` · `a_provider_that_does_not_provision_refuses_somebody_it_has_not_been_told_about` · `providers::tests::a_provider_that_does_not_provision_refuses_a_subject_nobody_linked` |
| I-05 | Mock identity is refused outside `demo` | `the_mock_identity_source_stops_the_process_starting_outside_a_demo` · `a_mock_identity_source_cannot_be_built_outside_a_demo` · `a_demo_may_have_one_and_still_starts` |
| I-06 | Every authentication path is exercised against a real issuer, not only a mock | the whole of `identity/tests/oidc.rs` runs against `identity::testing::Issuer`, a process that publishes a discovery document and a key set over a socket and signs with a key it holds |

The forgery cases are the point of I-06, and each is a named test:
`a_token_that_says_it_needs_no_signature_is_refused` *
`a_token_claiming_a_symmetric_algorithm_is_refused_before_a_key_is_used` *
`a_token_signed_by_a_key_the_issuer_does_not_publish_is_refused` *
`a_token_whose_payload_was_edited_after_signing_is_refused` *
`an_expired_token_is_refused_however_well_signed` *
`a_token_with_no_expiry_is_refused_rather_than_treated_as_valid_forever` *
`a_token_minted_for_another_service_does_not_sign_anybody_in_here` *
`an_issuer_nobody_accepted_is_refused_without_its_keys_being_fetched` *
`an_issuer_pointing_its_keys_at_another_origin_is_refused` *
`a_plain_http_issuer_that_is_not_on_this_machine_is_refused_before_a_socket_is_opened`.

A rotation is covered in both directions: `a_routine_key_rotation_does_not_lock_everybody_out` and
`a_key_identifier_that_exists_nowhere_is_refused_after_one_refetch`, with
`a_flood_of_unknown_key_identifiers_costs_one_refetch_not_one_each` for the cost of the second.

## People (U) — 5 of 5

| ID | Requirement | Guard |
|---|---|---|
| U-01 | Person state evaluated at the door on every entry kind | `somebody_suspended_mid_session_is_refused_on_their_next_request` · `a_suspended_person_is_refused_on_every_entry_kind` · `a_deactivated_person_cannot_open_a_ticket_even_with_a_valid_token` · `a_suspended_person_is_refused_at_the_next_entry_rather_than_at_the_next_sign_in` |
| U-02 | Deactivation revokes sessions, node tokens and activations atomically | `deactivating_somebody_stops_their_node_and_their_schedule_at_the_same_moment` · `directory::tests::deactivating_withdraws_sessions_node_tokens_and_activations_in_one_call` · `revoking_sessions_leaves_a_token_that_no_longer_resolves` |
| U-03 | Swarm roles and package tiers stay separate vocabularies | `a_tier_is_not_a_swarm_role_and_holding_one_package_says_nothing_about_another` |
| U-04 | Invitations expire and are single-use | `an_invitation_admits_somebody_once_and_then_never_again` · `invitations::tests::an_invitation_works_once` · `invitations::tests::an_invitation_stops_working_when_it_expires` · `invitations::tests::what_is_stored_is_not_the_invitation` |
| U-05 | Export and delete cover every store the key function names | `export_and_erase_reach_every_store_the_key_function_names_and_nobody_elses` (relational, knowledge index, time series) · `erasing_a_scope_removes_every_collection_in_it_and_nothing_outside_it` (against PostgreSQL) |

U-05 walks every store that keys by the one function: the relational rows, the knowledge index and the
time series. The graph and blob stores the design names do not exist in this tree yet, and each one added
belongs in `export_person` and `erase_person` beside the three that are there.

## Settings (N) — 5 of 5

| ID | Requirement | Guard |
|---|---|---|
| N-01 | One function resolves a setting and returns the winning scope | `each_scope_in_turn_wins_over_the_ones_below_it` · `one_persons_preference_is_not_another_persons` · `scope::tests::the_scopes_are_ordered_most_specific_first` |
| N-02 | A write is refused when the principal may not write that scope | `a_person_cannot_write_tenant_policy` · `root_writes_the_deployment_and_still_cannot_write_what_the_artifact_ships_with` · `scope::tests::a_person_writes_their_own_preference_and_not_policy` · `scope::tests::a_bot_has_no_preference_of_its_own` |
| N-03 | A locked scope makes lower scopes inert and says so | `a_locked_tenant_policy_makes_a_persons_own_preference_inert_and_says_so` · `a_write_under_a_lock_is_refused_rather_than_silently_having_no_effect` · `removing_the_lock_restores_the_preference_that_was_kept_underneath_it` |
| N-04 | An unknown or ill-typed key is refused at write | `a_key_nothing_declares_cannot_be_written_or_resolved` · `a_value_the_schema_refuses_never_reaches_the_store` · `schema::tests::a_value_of_the_wrong_type_is_refused` · `schema::tests::a_key_declared_twice_is_refused_rather_than_silently_replaced` |
| N-05 | No kernel code path reads a literal where a setting exists | the installation reads its tunables through `Settings::resolve` from `oshald::tunables` · `the_inventory_lists_every_setting_with_the_schema_that_declared_it_and_the_kernel_reads_them` · `a_declared_settings_default_is_not_also_a_literal_in_the_composition_root` |

The review gate for N-05 is textual: a declared default may not appear in the composition root outside
the declarations. Constants that are not declared settings — a lease length, a code's lifetime — are
not covered by it, because nothing yet makes them settings.

## Queue (Q) — 7 of 7

| ID | Requirement | Guard |
|---|---|---|
| Q-01 | Every envelope carries an idempotency key; a redelivery does not duplicate its effect | `in_process_delivery_does_finished_work_once` · `durable_delivery_does_finished_work_once_too` |
| Q-02 | Unacknowledged envelopes are re-queued with an attempt count and a visible pending set | `an_expired_lease_returns_the_work` · `retries_then_keeps` · `the_pending_set_is_visible`, each run by both transports |
| Q-03 | Exhausted envelopes land in a dead-letter queue with a cause and are replayable | `a_lease_that_expired_says_so_in_the_dead_letter_when_it_finally_gives_up` · `a_dead_letter_can_be_replayed`, run by both transports |
| Q-04 | Routing comes from registry data; a new ticket type needs no dispatcher change | `a_published_workflow_is_a_package_and_its_ticket_type_routes_once_it_is_serving` |
| Q-05 | A circuit opens per bot and per package and recovers on a probe | `breaker::tests::a_circuit_opens_only_after_the_threshold_of_consecutive_failures` · `breaker::tests::an_open_circuit_lets_exactly_one_probe_through_after_it_cools` · `breaker::tests::a_probe_that_succeeds_closes_the_circuit_and_one_that_fails_reopens_it` · `breaker::tests::one_bot_failing_does_not_stop_another` |
| Q-06 | An over-bound queue refuses with a named code | `a_full_queue_refuses`, run by both transports |
| Q-07 | The same workflow completes over both transports | `in_process_delivery_satisfies_the_contract` · `durable_delivery_satisfies_the_same_contract` · `durable_delivery_differs_in_the_one_way_it_is_meant_to` |


## Monitoring (H) — 8 of 8

| ID | Requirement | Guard |
|---|---|---|
| H-01 | Readiness enumerates dependencies and their states | `readiness_enumerates_dependencies_and_needs_no_credential` · `with_the_store_down_the_probe_still_answers_and_says_not_ready` · `readiness::tests::a_component_with_a_failed_dependency_does_not_report_ready` · `readiness::tests::a_store_that_comes_back_makes_the_installation_ready_without_a_restart` |
| H-02 | Metrics render in `demo` with no external scraper | `metrics_render_in_demo_mode_with_no_scraper_installed` · `metrics::tests::metrics_render_without_anything_else_installed` · `metrics_need_a_credential_like_everything_else_behind_the_door` |
| H-03 | Monitoring targets are inherited from declarations | `every_declared_bot_is_a_monitoring_target_without_a_configuration_edit` · `metrics::tests::registering_a_bot_registers_its_target_with_no_configuration_edit` |
| H-04 | An alert becomes a ticket through the normal door, deduplicated | `a_hundred_firings_of_one_problem_are_one_ticket` · `alerts::tests::the_same_problem_firing_twice_is_one_ticket` · `alerts::tests::a_different_problem_from_the_same_source_is_a_different_ticket` · `alerts::tests::resolving_a_problem_makes_the_next_occurrence_new_again` |
| H-05 | A remediation is declared, rate-limited, audited and runs as an activated principal | `remediation::tests::an_action_nobody_declared_cannot_run` · `a_remediation_nobody_activated_does_not_run_however_allowed_it_is` · `remediation::tests::running_too_often_in_the_window_is_refused_and_allowed_again_after_it` · `remediation::tests::every_attempt_is_recorded_with_who_it_ran_as` |
| H-06 | Repeated failure escalates to a person and stops | `remediation::tests::repeated_failure_escalates_to_a_person_and_stops_trying` · `remediation::tests::a_success_clears_the_count_towards_escalation` |
| H-07 | Alarms fire on the absence of expected data, not only on thresholds | `silence::tests::a_wedged_pipeline_alarms_on_silence_rather_than_on_a_number` · `silence::tests::a_source_that_never_reported_at_all_alarms_too` · `silence::tests::a_source_that_reports_on_time_is_not_quiet` |
| H-08 | A remediation completes only after its effect is verified; a failed check reopens and escalates | `remediation::tests::a_command_that_exited_cleanly_is_not_evidence_the_problem_is_fixed` · `remediation::tests::a_remediation_that_keeps_not_working_escalates_even_when_every_command_succeeded` · `remediation::tests::a_verified_fix_is_restored_and_clears_the_count` |

## Tracing (G) — 5 of 5

Requirement identifiers from
07 — Subsystem specifications, part 2 §N.

| ID | Requirement | Guard |
|---|---|---|
| G-01 | A trace identifier propagates across every transport and appears in every span of the unit | `one_unit_of_work_is_one_trace_from_the_request_to_the_phase_a_node_ran` · `a_node_running_a_phase_is_inside_the_same_unit_of_work_as_the_request` · `the_sign_in_stack_is_not_what_decides_a_unit_of_work` |
| G-02 | Spans are assembled from real records; a missing record is a visible gap | `deleting_one_record_leaves_a_gap_that_names_it_rather_than_a_trace_that_looks_whole` · `assemble::tests::a_missing_record_is_a_gap_and_never_a_span_somebody_made_up` · `assemble::tests::a_span_kind_this_reader_does_not_know_is_skipped_rather_than_guessed_at` · `assemble::tests::records_from_another_unit_of_work_are_not_swept_in` |
| G-03 | Call spans and cost events share identifiers and reconcile | `assemble::tests::cost_reconciles_to_the_call_span_that_named_it` · `assemble::tests::a_cost_naming_a_call_nobody_has_a_record_of_is_a_gap_rather_than_a_silent_total` · `cost_a_node_reported_is_money_the_trace_counts_and_cannot_attribute` · `an_amount_that_was_written_down_reads_back_as_the_same_integer` |
| G-04 | Trace attributes pass the redaction test | `observer::tests::a_span_attribute_is_scrubbed_like_every_other_field` · `assemble::tests::an_attribute_that_was_scrubbed_stays_scrubbed_through_assembly` · `a_span_carries_nothing_a_sink_would_have_scrubbed` |
| G-05 | Traces declare retention | `span::tests::a_retention_must_keep_something_and_must_not_keep_everything` · `span::tests::retention_decides_what_is_still_readable` · `assemble::tests::a_span_past_retention_leaves_a_gap_rather_than_a_shorter_trace_that_looks_whole` |

There are three span kinds and no more (N3), which is a closed enumeration rather than a convention:
`span::tests::a_span_kind_round_trips_and_nothing_else_parses`, and a record naming a fourth is skipped
rather than read as a span.

## Application management (A) — 7 of 7

Requirement identifiers from
05 — Subsystem specifications §D.

| ID | Requirement | Guard |
|---|---|---|
| A-01 | Install records provenance and is refused from an untrusted registry | `an_install_records_where_the_code_came_from` · `provenance_says_who_installed_it_rather_than_what_the_caller_claimed` · `two_builds_of_one_version_are_two_artifacts_and_the_record_says_which` · `a_package_installs_only_from_a_registry_row_somebody_trusted` |
| A-02 | Activation fails when a dependency or group member is not active | `a_package_whose_dependency_is_installed_but_not_serving_does_not_come_up` · `a_group_does_not_come_up_while_half_of_it_is_down` |
| A-03 | Granting is a distinct action from installing | `a_capability_the_manifest_never_asked_for_cannot_be_granted` · `the_inventory_is_the_loader_rather_than_a_list_somebody_maintains` (an installed package with no grants is listed and not usable) |
| A-04 | Uninstall does not delete package data unless explicitly chosen | `uninstalling_keeps_the_data_unless_somebody_says_otherwise` · `deleting_the_data_is_a_choice_that_has_to_be_made_explicitly` · `a_package_something_else_needs_cannot_be_uninstalled_out_from_under_it` · `a_serving_package_is_not_uninstalled_from_under_its_callers` |
| A-05 | The application inventory is generated, not written | `the_inventory_is_the_loader_rather_than_a_list_somebody_maintains` · `the_inventory_says_what_a_package_is_waiting_on_rather_than_only_that_it_is_down` · `what_the_inventory_shows_follows_the_loader_with_no_second_write` |
| A-06 | A per-person status probe runs in the caller's own session, never with a service credential | `Loader::probe` builds the host from the caller's context and takes no other · `a_status_the_application_reported_is_rendered_from_the_callers_own_session` · `a_service_cannot_read_a_persons_status_for_them` |
| A-07 | An unreachable or unresolvable probe renders as "cannot check", never as fact or zero | `an_unreachable_upstream_reads_as_cannot_check_rather_than_as_fact` · `an_error_status_is_cannot_check_even_when_its_body_has_numbers_in_it` · `a_package_that_is_not_serving_cannot_be_checked` |

## Dynamic loading (L) — 5 of 5

Requirement identifiers from
05 — Subsystem specifications §E.

| ID | Requirement | Guard |
|---|---|---|
| L-01 | Bots, tools and surfaces enter a registry only through a loaded package | `register_a_bot_outside_the_loader.rs` (compile-fail: ``method `converge` is private``) · `a_bot_enters_a_registry_by_its_package_being_loaded` · `registration_is_one_lifecycle_rather_than_one_per_kind_of_thing` |
| L-02 | Re-loading converges rather than duplicating | `loading_a_package_twice_converges_rather_than_duplicating` · `registrations::tests::loading_the_same_package_twice_leaves_one_registration` · `registrations::tests::a_declaration_the_new_manifest_dropped_is_gone_rather_than_left_behind` |
| L-03 | A duplicate bot name across packages is refused at load | `a_second_package_claiming_a_bot_name_is_refused_at_load` · `a_package_refused_at_registration_never_reaches_a_host` · `registrations::tests::a_refused_registration_leaves_the_registries_as_they_were` |
| L-04 | A tool is invisible to a package that did not declare it | `a_tool_is_invisible_to_a_package_that_did_not_declare_it` · `registrations::tests::a_package_sees_its_own_tools_and_not_another_packages` |
| L-05 | Unload drains in-flight work and fails open phases with a named reason | `unloading_drains_what_is_running_and_fails_what_waits_with_the_reason` · `unloading_gives_the_names_back_so_another_package_can_claim_them` · `a_surface_goes_down_with_the_package_that_declared_it` |

Unloading waits a bounded time for work the package's bots already hold, then withdraws what is
still waiting and fails each of those tickets with the reason in its history. A serving package cannot
be removed from under its callers (`a_serving_package_cannot_be_unloaded_from_under_its_callers`);
unloading is the path that takes it out of service first.

## Connectors (X) — 6 of 6, and X-07..X-10 and X-12 from the amendments

Requirement identifiers from
05 — Subsystem specifications §G.

| ID | Requirement | Guard |
|---|---|---|
| X-01 | A connector is declarable without kernel code changes for the supported auth shapes | `a_connector_is_added_by_declaring_it` · `declaring_a_connector_is_one_call_and_no_kernel_change` · `every_fault_in_a_declaration_is_reported_at_once` |
| X-02 | A credential value never appears outside the intent boundary | `serialize_a_secret.rs` (compile-fail) · `a_read_runs_and_what_comes_back_carries_no_credential` (the handler echoes the material on purpose and it still does not get out) · `a_result_cannot_carry_material_out_even_when_the_remote_system_echoes_it` · `a_span_attribute_is_scrubbed_like_every_other_field` |
| X-03 | A write action requires `Ctx<Confirmed>` | `write_through_a_connector_unconfirmed.rs` (compile-fail: ``expected `&Ctx<'_, Confirmed>`, found `&Ctx<'_, Write>` ``) · `a_write_is_refused_without_a_confirmation_and_the_refusal_is_audited` · `a_write_runs_on_a_confirmed_context` |
| X-04 | Every action and refusal is audited with principal, connector and operation | `the_audit_keeps_refusals_as_well_as_the_things_that_worked` · `a_write_is_refused_without_a_confirmation_and_the_refusal_is_audited` · `an_intent_the_connector_does_not_authorize_never_reaches_the_boundary` · `a_revoked_connection_stops_working_at_the_next_action` |
| X-05 | Expiry and revocation are owner-visible states and refuse cleanly | `an_expired_connection_refuses_cleanly_rather_than_failing_at_the_provider` · `a_revoked_connection_stops_working_at_the_next_action` · `liveness_moves_from_connected_through_expiring_to_expired` · `what_an_owner_sees_carries_the_state_each_connection_is_in` |
| X-06 | A shared connector carries its own grants, distinct from personal ones | `a_shared_connection_carries_its_own_grants` · `a_viewer_grant_on_a_shared_connection_is_not_enough_to_write_through_it` · `one_persons_connection_is_not_another_persons` · `a_person_uses_their_own_connection_rather_than_the_shared_one` |
| X-07 | Connections are keyed per account; selection is named, then default, then sole candidate; recency is not a rule and ambiguity refuses | `a_second_mailbox_is_a_second_connection_rather_than_a_replacement` · `two_accounts_and_no_way_to_choose_refuses_and_lists_them_in_a_stable_order` · `a_named_account_wins_and_a_name_that_is_not_theirs_does_not_fall_back` · `the_persons_default_is_used_when_they_name_none` · `recency_is_not_a_rule_so_using_an_account_again_does_not_make_it_the_choice` · `a_default_cannot_name_somebody_elses_account` |
| X-08 | Webhook ingress is an admission entry kind: signature-verified, declared in advance, replay-deduplicated | `EntryKind::Webhook` and `Credential::Signed`, verified by the `Webhooks` identity source · `a_signed_delivery_on_a_declared_hook_is_admitted_as_its_service` · `an_unsigned_delivery_is_refused` · `a_delivery_signed_with_the_wrong_secret_is_refused` · `a_signature_over_a_different_body_is_refused` · `a_delivery_on_a_hook_nobody_declared_is_refused` · `a_replayed_delivery_is_refused_the_second_time` · `a_forged_delivery_does_not_use_up_the_real_ones_identifier` · `a_hook_cannot_be_declared_to_act_as_a_person` |
| X-12 | A streaming upstream terminates in the kernel with one process-wide connection, reference-counted fan-out and explicit staleness; no store module has a path to the key | `many_subscribers_share_one_connection_and_the_last_one_out_closes_it` · `a_value_says_how_current_it_is_and_an_old_one_says_it_is_stale` · `no_store_module_has_a_path_to_an_upstream_key` |
| X-09 | One outbound client: retry and backoff honouring the provider's hint, a per-provider rate bucket, one error shape | `a_transient_failure_is_retried_with_a_backoff_that_doubles` · `the_providers_retry_hint_is_honoured_over_the_clients_own_backoff` · `a_hint_longer_than_the_ceiling_is_capped_rather_than_obeyed_forever` · `a_permanent_failure_is_not_retried` · `every_provider_fails_in_the_same_shape` · `one_bucket_per_provider_is_shared_by_every_caller` · `retries_draw_on_the_same_bucket_as_first_attempts` |
| X-10 | Risk is derived from declared operations, and a declaration asserting its own is rejected | `risk_is_derived_from_what_the_operations_do` · `a_declaration_asserting_its_own_risk_level_is_rejected` |

The "stable tiebreak" rung of X-07 is realised as the stable order the ambiguity refusal lists its
candidates in, not as a silent pick: the acceptance for X-07 is that no action crosses accounts silently,
and a tiebreak that chose would be exactly that.

## Knowledge and retrieval (R) — 9 of 10

Requirement identifiers from
05 — Subsystem specifications §H.

| ID | Requirement | Guard |
|---|---|---|
| R-01 | A retrieval returns only chunks the principal may read | `one_persons_corpus_does_not_answer_another_persons_question` · `a_retrieval_returns_only_what_the_caller_may_read` · `a_passage_somebody_may_not_read_is_never_a_candidate_rather_than_filtered_after` · `ingesting_into_a_collection_the_caller_cannot_write_is_refused` |
| R-02 | Collections are scoped by the single key function plus the package namespace | `a_corpus_in_one_tenant_is_invisible_in_another` · `a_collection_one_person_declared_is_not_visible_to_another` · `a_tenant_collection_is_visible_to_everybody_in_that_tenant` · `the_same_name_in_two_packages_is_two_collections` |
| R-03 | Hybrid retrieval degrades to lexical when embeddings are unavailable, and says so | `an_installation_with_no_embedder_still_answers_and_says_it_is_degraded` · `retrieval_with_no_embedding_function_is_lexical_and_says_so` · `retrieval_with_an_embedding_function_is_hybrid_and_not_degraded` |
| R-04 | Every result carries a document id and a source class | `every_result_carries_a_document_and_a_source_class` · `what_a_retrieval_returns_can_be_cited_back_to_where_it_came_from` · `web_content_is_cited_as_web_so_a_reader_knows_who_wrote_it` |
| R-05 | A package may not create or read a reserved collection | `a_package_cannot_take_a_kernel_collection_name` · `a_package_cannot_seed_a_kernel_collection` · `the_kernel_may_use_its_own_names` |
| R-06 | `demo` retrieves with no network dependency | `a_demo_retrieves_with_nothing_else_installed` · `the_same_text_always_embeds_to_the_same_vector` · `text_sharing_words_points_in_a_more_similar_direction_than_text_that_does_not` |
| R-07 | Retrieval runs index-backed queries and never degrades to a full scan; a missing index fails rather than scanning | `retrieval_scores_what_the_index_returns_and_never_the_whole_corpus` · `a_collection_with_no_index_fails_rather_than_being_scanned`; `Index::verify_index` asserts coverage |
| R-09 | The index pins its embedding width, and changing the model is a reindex | `retrieval::tests::the_index_pins_the_width_of_its_vectors` · `retrieval::tests::changing_the_embedding_model_is_a_reindex_of_everything_held` |
| R-10 | Deleting a source deletes its chunks | `retrieval::tests::deleting_a_source_deletes_its_chunks_and_it_stops_answering` · `retrieval::tests::a_person_cannot_delete_a_document_in_somebody_elses_collection` |

The scoping defect this rail exists to prevent was found by a test rather than by review: keying the
index on the collection name alone put one person's documents in another person's answer, and
`a_retrieval_returns_only_what_the_caller_may_read` failed until the contents were keyed by the scope
as well.

Candidates come from an inverted index maintained with the contents, and vector similarity is computed
over those candidates. R-08 (one fusion implementation across store engines) is not claimed: there is
one retrieval engine, so "identical across engines" has nothing yet to be asserted against.

## Token (M) — 4 of 5

Requirement identifiers from
05 — Subsystem specifications §I.

| ID | Requirement | Guard |
|---|---|---|
| M-01 | A series declares retention; an unbounded one is refused at load | `a_series_nobody_gave_a_retention_cannot_be_declared_at_all` · `a_series_cannot_be_declared_without_a_retention` · `a_rollup_wider_than_the_retention_is_refused` · `a_declaration_that_does_not_check_never_becomes_a_series` |
| M-03 | Rollups are declared and produced by the engine, not by per-package jobs | `a_declared_rollup_reduces_each_bucket_the_way_it_said_it_would` · `a_bucket_width_the_series_does_not_declare_is_refused` · `a_declared_rollup_answers_from_the_rail_with_nothing_installed` · `an_empty_bucket_has_no_number_rather_than_a_zero` |
| M-04 | Late-point behaviour is declared and honoured | `a_late_point_is_rejected_where_the_series_says_to_reject_it` · `a_late_point_is_kept_where_the_series_says_to_accept_it` · `a_corrected_reading_replaces_the_one_it_corrects_where_the_series_reconciles` · `a_reading_taken_twice_at_one_instant_is_one_reading_where_the_series_reconciles` · `a_series_that_accepts_late_points_keeps_two_readings_at_one_instant` |
| M-05 | Series are scoped by the single key function | `two_tenants_with_a_series_of_the_same_name_have_two_series` · `a_package_series_is_scoped_to_the_person_who_declared_it` · `a_series_nobody_created_in_this_scope_is_not_there` |

Metrics are a series rather than a separate system (I5), which is what makes the single-artifact claim
true rather than a plan: `metrics_are_a_series_rather_than_a_separate_system`,
`the_kernel_declares_its_own_series_at_start_with_retentions_on_them` and
`the_engine_sweeps_what_is_past_retention_on_the_kernels_own_series_too` — the kernel is subject to its
own retention rule.

M-02 (the same queries running on two engines) is not claimed. Queries use the trait vocabulary and
never engine SQL, and the in-memory engine implements the whole trait, but this tree has one engine, so
a passing parity test would be evidence about one engine rather than about portability.

## Bot composition (B-13..B-16) — 4 of 4

Requirement identifiers from
07 — Subsystem specifications, part 2 §Q.

| ID | Requirement | Guard |
|---|---|---|
| B-13 | Assembly follows the fixed frame; a package cannot alter the system contract | there is no `Slot::Contract` to fill · `a_package_cannot_get_content_in_front_of_the_system_contract` · `the_slots_are_assembled_in_frame_order_whatever_order_they_were_filled_in` · `an_attempted_contract_override_is_dropped_and_recorded` · `content_that_tries_to_look_like_a_frame_boundary_is_defanged_and_recorded` |
| B-14 | Tool binding is the intersection of declared tools and caller grants, per invocation | `tools_are_bound_per_invocation_from_what_is_declared_and_what_is_held` · `a_grant_withdrawn_takes_effect_on_the_next_invocation` · `tool_binding_is_the_intersection_of_what_is_declared_and_what_is_held` · `a_bot_with_no_bound_tools_gets_no_tool_slot_rather_than_an_empty_one` |
| B-15 | Structured output is schema-validated and a parse failure escalates | `structured_output_that_does_not_parse_escalates_rather_than_falling_back` · `structured_output_that_parses_is_the_decision_the_phase_asked_for` · `prose_where_a_decision_was_expected_escalates_rather_than_falling_back` · `every_fault_is_reported_at_once` |
| B-16 | Assembly provenance explains the run while the assembled prompt reaches only the provider, never log sinks | `composition::the_assembled_prompt_reaches_the_provider_without_entering_log_sinks` · `a_run_can_be_explained_from_what_was_recorded_without_the_prompt_being_kept_anywhere_else` · `what_the_escalation_shows_is_scrubbed_like_every_other_detail` |

Persona is data and carries no authority (Q2): it is a slot below the contract and it is scrubbed on
the way in, which `persona_text_is_data_and_is_scrubbed_like_everything_else` and
`everything_in_a_slot_is_scrubbed_because_the_whole_system_text_is` hold.

## Person model (J) — 7 of 7

Requirement identifiers from
07 — Subsystem specifications, part 2 §P.

| ID | Requirement | Guard |
|---|---|---|
| J-01 | History, profile and derivations are separable and separately deletable | `what_a_person_said_and_what_was_inferred_are_different_stores` · `deleting_a_source_deletes_what_was_inferred_from_it` · `a_derivation_with_a_second_source_survives_losing_the_first` · `forgetting_everything_leaves_nothing_in_any_of_the_three` |
| J-02 | Every derivation carries source and confidence | `an_inference_from_nothing_cannot_be_written` · `an_inference_from_an_event_nobody_recorded_is_refused` · `a_confidence_outside_zero_to_one_is_not_a_confidence` · `an_inference_comes_back_marked_as_one_with_its_confidence` |
| J-03 | Recall is task-scoped, grant-filtered and produces a receipt | `a_bot_is_told_the_slice_the_task_justifies_and_not_the_profile` · `a_caller_without_the_capability_gets_nothing_to_put_in_the_prompt` · `the_person_can_read_what_was_recalled_about_them_and_for_what` · `a_receipt_says_what_was_asked_for_and_not_held_as_well_as_what_came_back` |
| J-04 | Enrichment requires consent and is not a side effect of an unrelated entry | `an_enrichment_nobody_consented_to_does_not_happen` · `asking_a_question_does_not_infer_anything_about_the_person_who_was_asked_about` · `recalling_writes_no_derivation_so_asking_a_question_does_not_infer_anything` |
| J-05 | A learned signal cannot alter grants, policy or gates | `learning_cannot_widen_what_somebody_may_do` · `a_learned_signal_cannot_widen_access` · `the_refusal_is_about_the_key_rather_than_what_it_wanted_to_write` |
| J-06 | Proactive actions are rate-limited, budgeted and switchable off | `acting_unasked_has_a_rate_limit_a_budget_and_an_off_switch` · `acting_unasked_stops_at_the_rate_limit` · `acting_unasked_stops_at_the_budget_even_inside_the_rate_limit` · `there_is_an_off_switch_and_it_takes_effect_at_once` |
| J-07 | Export and correction cover all three stores | `an_export_covers_all_three_stores` · `a_person_can_correct_what_they_said_and_not_what_was_inferred` · `one_persons_memory_is_not_anothers` |

The recall guard is what makes Q4 true: the slice a bot is told is chosen by the guard, from the
justification the workflow phase supplied, and a field nobody justified is absent from the prompt that
was actually sent — `a_bot_is_told_the_slice_the_task_justifies_and_not_the_profile` reads the prompt
back out of the run record rather than out of the object that built it. What a person said outranks
what was inferred about the same field
(`what_a_person_said_outranks_what_was_inferred_about_the_same_field`), because a correction is only a
correction if it is what comes back.

## Node network (Z) — 7 of 7, and Z-08 and Z-09 from the amendments

Requirement identifiers from
07 — Subsystem specifications, part 2 §S.

| ID | Requirement | Guard |
|---|---|---|
| Z-01 | Enrolment proves ownership and issues a device-bound, owner-scoped, leased token | `a_token_from_one_node_is_not_a_token_for_another` · `a_lease_lapses_and_a_heartbeat_renews_it` · `a_lease_holds_until_it_expires_and_not_after` · `what_the_kernel_stores_cannot_be_replayed_as_the_token` |
| Z-02 | Admission is identical across LAN, internet and overlay | `admission_is_the_same_over_a_lan_the_internet_and_an_overlay` |
| Z-03 | Overlay membership grants no authority by itself | `being_on_the_overlay_without_a_token_is_not_an_entry_at_all` · `every_path_names_itself_and_none_of_them_is_special` |
| Z-04 | An expired lease releases in-flight envelopes for re-queue | `a_node_that_stops_heart_beating_releases_the_work_it_was_holding` · `an_expired_lease_says_it_expired_rather_than_that_the_node_is_unknown` |
| Z-05 | Node capabilities are declared and granted; undeclared ones are not linked | `a_node_is_enrolled_with_capabilities_and_an_undeclared_one_is_not_linked` · `a_code_carries_what_the_node_will_be_allowed_to_do` · `holding_the_capability_is_not_enough_if_the_node_was_not_enrolled_with_it` |
| Z-06 | Device operations run on the owning node with kernel-side authorization and audit | `a_device_call_from_somebody_who_does_not_own_the_node_refuses_and_is_audited` · `a_device_call_from_somebody_who_does_not_own_the_node_is_refused_and_recorded` · `every_attempt_is_on_the_record_whichever_way_it_went` |
| Z-07 | Enrolment is completable without editing source or hand-placing a token | `a_machine_enrols_from_a_code_with_nothing_placed_by_hand` · `a_code_enrols_a_machine_once_and_then_never_again` · `a_code_stops_working_when_it_expires` · `what_is_stored_is_not_the_code` |
| Z-08 | Authorization filters candidate machines before any preference, and enumeration is scoped | `authorization_filters_the_machines_before_any_preference_and_a_foreign_pin_is_nothing` |
| Z-09 | A physical act carries a safety class; kinetic acts are human-issued with the fence re-checked at execution; stop and abort are confirmation-exempt; a lost link fails closed; every command is audited | `a_kinetic_act_needs_a_person_a_confirmation_and_a_fence_that_holds_when_it_runs` · `stop_and_abort_need_no_confirmation_no_person_and_no_link` · `a_lost_link_fails_everything_but_stopping_closed` · `an_actuator_needs_a_confirmation_but_not_a_person` · `every_command_is_on_the_record_whichever_way_it_went` |

## Ambient capture (E) — 6 of 6

Requirement identifiers from
07 — Subsystem specifications, part 2 §O.

| ID | Requirement | Guard |
|---|---|---|
| E-01 | Capture is off by default and needs a scoped, revocable consent record | `nobody_is_captured_until_they_have_agreed` · `nobody_can_start_a_capture_they_have_not_consented_to` · `an_agreement_covers_its_device_and_surface_and_nothing_else` · `revoking_mid_session_stops_that_person_being_captured_at_the_next_segment` · `a_person_heard_who_did_not_consent_is_dropped_rather_than_kept_as_unknown` |
| E-02 | Raw media does not leave the capturing node without an explicit person action | `a_session_sends_transcripts_and_never_media` · `raw_media_leaves_only_because_somebody_who_was_heard_asked` · `raw_media_never_shows_itself_in_a_log` |
| E-03 | An unmatched speaker is labelled unknown | `a_voice_nobody_enrolled_is_unknown_rather_than_the_nearest_guess` · `two_people_equally_close_is_an_ambiguity_and_an_ambiguity_is_unknown` · `a_voice_nobody_enrolled_is_kept_as_unknown_and_attributed_to_nobody` · `the_same_voice_is_attributed_the_same_way_every_time` |
| E-04 | Capture shows an active indicator and stops in one action | `stopping_is_one_action_and_nothing_is_taken_after_it` |
| E-05 | Captured content has declared retention and is deletable by the captured person | `what_was_kept_goes_when_its_retention_does` · `a_captured_person_can_delete_everything_they_said` |
| E-06 | `demo` transcribes with no network | `the_transcriber_that_ships_needs_no_network` |

Captured text reaches a person's memory through one gate (O7): `into_person_model` refuses without
enrichment consent, and an unknown speaker's words are never an event about anybody
(`captured_text_reaches_the_person_model_only_with_consent`,
`an_unknown_speaker_is_never_an_event_about_anybody`).

## Producers (W) — 5 of 5

Requirement identifiers from
05 — Subsystem specifications §K.

| ID | Requirement | Guard |
|---|---|---|
| W-01 | Every producer emits the same package shape and passes the same gate | `every_producers_output_passes_the_same_gate_as_anything_else` · `every_producer_emits_the_same_shape` |
| W-02 | Packing is reproducible and records producer, input hash and SDK range | `the_same_inputs_produce_a_byte_identical_manifest` · `inputs_in_a_different_order_are_the_same_inputs` · `the_package_records_its_producer_its_inputs_and_its_sdk_range` · `different_inputs_hash_differently` |
| W-03 | Imported scripts are quarantined; tools are minimised to declared capabilities | `imported_scripts_are_quarantined_and_the_manifest_names_none_of_them` · `an_imported_skill_asking_for_an_undeclared_capability_does_not_become_a_package` · `a_script_name_that_would_climb_out_of_the_package_is_refused` |
| W-04 | A producer cannot activate its output or write into the kernel tree | `a_produced_package_arrives_installed_and_is_not_serving` · `a_producer_cannot_write_into_the_kernel_tree` · `a_producer_cannot_write_into_the_kernel_tree_however_the_path_is_spelled` · `a_producer_cannot_reach_the_loader_it_would_need_to_activate_its_own_output` |
| W-05 | A produced package carries a runnable test catalog | `a_package_with_no_tests_is_not_emitted` · `a_produced_package_with_no_tests_cannot_reach_tested_at_the_loader` |

The gate test found a real gap on its first run: producers emitted packages with no status route, which
every package must declare (P-07), so the gate refused all four. The packer now requires one
(`a_package_that_reports_no_status_is_not_emitted`) rather than the test being loosened.

## Token optimisation (K) — 7 of 7

Requirement identifiers from
07 — Subsystem specifications, part 2 §M.

| ID | Requirement | Guard |
|---|---|---|
| K-01 | Optimisation runs over recorded runs, never on live person work | `a_live_ticket_is_never_the_ground_a_candidate_is_compared_on` · `the_optimiser_reads_finished_runs_and_writes_only_through_settings` |
| K-02 | A promotion needs judged savings net of judging cost and non-inferior quality | `a_cheaper_candidate_that_is_worse_is_rejected` · `a_saving_smaller_than_what_judging_it_cost_is_not_a_saving` · `a_candidate_wins_on_savings_net_of_judging_with_quality_no_worse` · `a_tie_keeps_the_incumbent` |
| K-03 | A non-reproducible replay is disqualified and reported | `an_incumbent_that_does_not_reproduce_disqualifies_the_comparison` |
| K-04 | Promotion is a scoped settings write, audited and reversible | `promotion_is_a_settings_write_at_a_scope_and_reverting_restores_what_was_there` · `only_a_winning_candidate_is_promoted` · `a_promotion_cannot_reach_a_scope_its_author_could_not_write_by_hand` |
| K-05 | Claimed savings reconcile against the cost ledger | `a_claimed_saving_has_to_show_up_in_the_ledger` |
| K-06 | Phase elision needs human approval | `eliding_a_phase_needs_a_person_and_a_bot_cannot_promote_it` · `the_levers_are_ordered_by_how_hard_they_are_to_undo` |
| K-07 | A verdict carries its mode, and deterministic and model verdicts are never blended | a score is a `Quality { mode, value }`, never a bare number · `a_deterministic_verdict_is_never_compared_with_a_model_verdict` |

## Control-plane amendments (C-09..C-28) — 20 of 20

Requirement identifiers from
09 — ADR sweep amendments.

| ID | Requirement | Guard |
|---|---|---|
| C-09 | Secrets are encrypted at rest, and a missing key refuses reads, writes and deletes with no plaintext fallback | `what_is_kept_is_ciphertext_and_it_opens_to_the_material` · `without_a_key_reads_writes_and_deletes_are_all_refused` · `a_different_key_does_not_open_what_another_sealed` · `a_row_moved_onto_another_reference_does_not_open` · `a_malformed_key_is_refused_rather_than_treated_as_none` · `an_installation_seals_secrets_and_one_started_without_a_key_refuses_them` |
| C-10 | A materialised credential lives in a single-user ephemeral session that revokes its lease and wipes its storage at teardown | `the_tool_reads_the_file_and_nothing_is_left_after` · `a_tool_that_panics_still_leaves_nothing_behind` · `two_sessions_never_share_a_directory` |
| C-11 | Refusal auditing is throttled per caller | `a_refusal_flood_from_one_caller_does_not_grow_the_audit_without_bound` · `a_refusal_flood_from_one_caller_is_counted_exactly_and_recorded_boundedly` · `one_caller_flooding_does_not_throttle_another` |
| C-12 | A credential-selection boundary rejects an unknown key rather than dropping it, and each owner receives only its own keys | `an_unknown_name_is_refused_rather_than_dropped` · `an_owner_receives_only_their_own_keys_even_when_the_name_exists_elsewhere` · `every_named_key_resolves_for_its_owner` |
| C-13 | An executor credential only narrows a business grant, never widens it, whatever the transport | `holding_the_capability_is_not_enough_if_the_node_was_not_enrolled_with_it` (the machine narrows) · `owning_the_node_is_not_enough_without_the_capability` (the machine never widens) · `admission_is_the_same_over_a_lan_the_internet_and_an_overlay` (the path is not an input) |
| C-14 | Queued work records intent, not authority; rights are re-resolved at execution | `a_person_suspended_while_their_work_waits_stops_that_work` · `work_whose_asker_is_still_active_runs` · `an_envelope_kept_for_a_changed_generation_stays_kept_after_a_restart` |
| C-15 | Grants combine as permission, scope and field-set tuples; dimensions are not unioned independently | `grants_are_whole_tuples_and_their_dimensions_do_not_combine`; `Ctx::holds` and `Envelope::permits` both ask whether one held tuple covers the request |
| C-16 | Authorization is enforced inside the data operation: predicates before paging, totals and ordering; updates checked against current and proposed ownership | `authorization_is_applied_inside_the_query_before_paging_totals_and_ordering` · `an_update_is_checked_against_the_row_as_it_is_and_as_it_would_become` (both against PostgreSQL) |
| C-17 | A revocation and the write it revokes share one transaction and version protocol | `a_revocation_that_comes_first_refuses_the_write_already_admitted_and_says_so` · `a_write_that_lands_first_is_recorded_first_and_the_next_one_is_refused` · `a_race_between_a_write_and_a_revocation_is_decided_by_the_recorded_order` |
| C-18 | An unknown permission identifier denies, including for an administrator | `a_capability_nobody_linked_is_denied_even_to_root` |
| C-19 | Forbidden and missing return the same answer | `a_missing_ticket_a_malformed_identifier_and_somebody_elses_ticket_are_one_answer` |
| C-20 | Credential endpoints are enumeration-safe | `a_guessed_invitation_learns_nothing_from_the_answer` · `an_unknown_a_used_and_an_expired_invitation_are_refused_with_one_answer` · `a_code_stops_working_when_it_expires` |
| C-21 | A machine-to-user call carries a signed, single-use delegation grant bound to workload, user, method, canonical path, body digest, audience and scope | `a_grant_redeems_once_for_exactly_the_request_it_names` · `every_binding_is_checked_and_the_refusal_names_the_one_that_failed` · `another_audience_a_forged_signature_and_an_expired_grant_are_refused` · `paths_are_compared_in_canonical_form` |
| C-22 | Untrusted content is fenced with its provenance, and leaves the untrusted class only by deterministic validation or an exact-digest approval | `untrusted_content_is_fenced_with_where_it_came_from_and_cannot_close_the_fence` · `promotion_by_approval_needs_the_exact_digest` · `promotion_by_validation_needs_the_check_to_pass` |
| C-23 | A system-service principal does not read or write person-owned rows | `a_system_service_cannot_open_the_rows_that_belong_to_a_person` |
| C-24 | Root is transferable and never removable | `root_can_be_handed_over_and_never_taken_away` · `only_root_may_hand_root_over` |
| C-25 | A failed privilege-store read serves no stale snapshot | `an_unreachable_authority_store_refuses_rather_than_serving_a_stale_answer` |
| C-26 | A break-glass operator path survives loss of the authority store | `root_still_gets_in_when_the_authority_store_is_gone_and_it_is_said_out_loud` |
| C-27 | Budget enforcement fails open on an infrastructure gap and closed on a definite breach | `an_unreadable_budget_ceiling_allows_and_says_so` · `a_readable_ceiling_that_is_breached_still_refuses` · `a_ceiling_nobody_could_read_allows_rather_than_refusing_everybody` |
| C-28 | A runaway kill switch trips on execution count, not dollars | `a_dispatch_loop_is_stopped_on_count_before_cost_accrues` |

C-17 is enforced by the ordering every scoped write goes through: a context carries the version of its
principal's authority from before its grants were read, a revocation moves the version on, and a write
compares and happens under the same lock, which records the order. The ordering is the kernel's, in
process; a second kernel process would need it in the database to share it.

C-14: an envelope carries the ticket, the phase and the capabilities the phase may use — what was asked —
and no credential. Whether the ticket's owner may still act is read from the directory when the envelope
is claimed, so a suspension takes effect on waiting work rather than on the next request only; the
envelope is kept as a dead letter with the reason, not completed. C-23 is enforced where a scoped store
handle is made: person-owned rows are the rows under the person scope, and a service principal cannot
open it. Tenant rows that name an owner, such as tickets, are the tenant's.

C-20's timing half is argued rather than measured: every credential here is looked up by the digest of
what was presented, so an unknown credential and a wrong one cost the same lookup, and there is no
account-then-secret path whose two halves could differ in time. A timing test in a shared CI runner
would measure the runner.

## Package and queue amendments (P-09..P-20, Q-08..Q-13) — 18 of 18

Requirement identifiers from
09 — ADR sweep amendments.

| ID | Requirement | Guard |
|---|---|---|
| P-09 | Dependencies block uninstall while dependents exist, and an orphan does not cascade | `a_package_something_else_needs_cannot_be_uninstalled_out_from_under_it` · `uninstalling_a_dependent_leaves_what_it_depended_on` |
| P-10 | Deactivate and uninstall tear down the package's schedules | `deactivating_a_package_takes_its_schedules_down` · `uninstalling_a_package_takes_its_schedules_down_too` |
| P-11 | Tool names are global; a collision fails the load closed | `a_tool_name_another_active_package_owns_fails_the_load_closed` · `a_tool_name_another_package_owns_is_refused_rather_than_repointed` |
| P-12 | A schedule target resolves to the exact package-owned export, with no fallback | `a_schedule_targeting_a_route_its_package_does_not_serve_does_not_load` · `a_schedule_ticks_to_its_own_packages_route_once_per_due_instant` · `deactivating_a_package_takes_its_schedules_down` |
| P-13 | An empty capability grant is the narrowest set, never unrestricted | `an_empty_grant_is_the_narrowest_set_rather_than_everything` |
| P-14 | Visibility and authorization are separate axes: publishing never confers the right to call, and depending on a private export fails closed | `publishing_a_tool_makes_it_importable_and_never_callable_by_itself` |
| P-15 | A manifest declares the access tiers it supports and its default, validated at load; deny is always available | `a_manifest_read_from_a_file_without_an_access_mapping_fails_validation` · `an_access_mapping_that_does_not_hold_together_fails_validation` · `only_a_tier_the_package_declared_can_be_granted_and_deny_always_can` |
| P-16 | Install presents the package's blast radius as the confirmation; trusting a registry is not consent | `install` takes the `BlastRadius` the person confirmed · `an_install_is_refused_when_the_package_would_do_more_than_the_confirmation_showed` · `the_radius_names_routes_migrations_schedules_and_capabilities` · `what_a_new_version_adds_is_exactly_what_the_person_did_not_see` |
| P-17 | A package offered by two registries fails closed rather than choosing a source | `a_package_offered_by_two_trusted_rows_is_refused_rather_than_chosen` · `a_package_offered_by_one_trusted_row_comes_from_that_row` |
| P-18 | Package bots launch through a substrate seam with a platform-fixed image; a launch specification has no image field | `launch_a_bot_in_its_own_image.rs` (compile-fail: ``struct `LaunchSpec` has no field named `image` ``) · `a_launch_request_naming_its_own_image_is_refused` · `a_package_bot_launches_through_the_substrate_in_the_platforms_image_and_only_if_registered` |
| P-19 | Hooks are called as the person over a fenced rail with per-package failure isolation | `one_packages_failure_or_timeout_does_not_block_the_others_or_the_caller` · `a_hook_must_name_a_route_its_package_serves` |
| P-20 | A surface-to-shell bridge carries only declared operations, defaulting to none | `a_surface_bridge_with_no_declared_operations_carries_nothing` · `a_surface_bridge_carries_exactly_what_its_package_declared` · `a_bridge_operation_the_shell_does_not_have_fails_validation` |
| Q-08 | An envelope whose ticket is terminal is acknowledged and skipped | `an_envelope_whose_ticket_ended_while_it_waited_runs_nothing` |
| Q-09 | Work is scheduled per tenant with a limit, so one tenant cannot monopolise workers | `a_saturating_tenant_does_not_starve_another`, run by both transports · `a_tenant_holding_its_share_of_workers_waits_while_another_is_served` |
| Q-10 | Privileged tools are reachable only through queue-mediated dispatch, never directly or by an assistant | `a_privileged_tool_runs_only_as_a_dispatched_phase_however_the_caller_was_admitted` |
| Q-11 | An intake is acknowledged only after its durable commit; a landing failure answers so the sender retries | `an_intake_that_could_not_land_answers_so_the_sender_retries_and_the_retry_lands_once` |
| Q-12 | A retry after an unknown outcome escalates to review; blind resubmission is disallowed | `Delivery::Unknown` is held, never redelivered: `an_unknown_outcome_is_held_for_review`, run by both transports · `an_unknown_outcome_is_still_held_for_review_after_a_restart` · at the provider rail, `a_write_that_got_no_answer_is_not_sent_again_and_needs_review` · `a_read_that_got_no_answer_is_asked_again` |
| Q-13 | A schedule tick keys off the due instant: a missed window expires, and a restart or replica neither double-fires nor skips | `a_schedule_ticks_to_its_own_packages_route_once_per_due_instant` · `a_missed_window_expires_rather_than_catching_up` · `a_due_instant_fires_once_however_many_times_it_is_offered` · `a_restart_inside_the_grace_window_still_fires_rather_than_skipping` |

A schedule whose package is deactivated comes back when the package is activated again, and its
activation does not: declaring a schedule was never activating it, and neither is reactivating the
package it belongs to. `a_schedule_nobody_activated_does_not_tick` holds the ADR-157 half of that.

Every identifier in this family is claimed. The hook rail bounds each package's call by a turn and calls
them one after another, so the worst case is the sum of the turns rather than the longest one; no
package's failure or silence stops the next from being called.

## Workflow (F)

| ID | Requirement | Guard |
|---|---|---|
| F-01 | A published workflow becomes a package and passes the package gate | `a_published_workflow_is_a_package_and_its_ticket_type_routes_once_it_is_serving` · `a_workflow_naming_a_bot_nothing_provides_does_not_activate` |
| F-02 | Validation is total before install; an unresolved node refuses | `every_fault_in_the_set_is_reported_at_once_and_nothing_loads` · `a_phase_that_names_no_bot_is_a_load_error_not_a_runtime_surprise` |
| F-03 | The shape is derived from the definition | one `WorkflowDef`: `a_valid_set_loads_and_answers_by_ticket_type` |
| F-04 | An approval gate names an approving principal and produces a confirmed context | `approve` takes `Ctx<Confirmed>` in its signature · `there_is_one_way_to_approve_and_reporting_an_outcome_is_not_it` · `a_person_holding_the_gates_tier_releases_it_with_a_confirmed_context` · `a_person_below_the_gates_tier_cannot_release_it_even_confirmed` · `a_bot_cannot_release_a_gate_whatever_tier_it_holds` · `a_gate_naming_an_approver_who_could_not_have_done_the_work_does_not_load` |
| F-05 | Every run records its definition version, inputs, per-phase outcome and cost | `every_run_has_a_record_of_its_definition_its_moves_and_its_cost` · `two_runs_of_the_same_workflow_are_comparable_because_they_ran_the_same_definition` · `a_record_is_assembled_from_the_history_in_the_order_it_happened` · `the_same_definition_is_the_same_version_and_any_change_is_a_new_one` |
| F-06 | Iteration and per-run budget are bounded by declaration and enforced at dispatch | `a_phase_dispatched_as_many_times_as_its_workflow_allows_is_not_dispatched_again` · `a_run_that_has_spent_its_budget_is_not_dispatched_again` · `cost_a_node_reported_does_not_count_against_the_run_budget` · `a_workflow_that_declares_bounds_of_nothing_does_not_load` |
| F-07 | Tickets form a tree and cost aggregates through every descendant | `a_parents_cost_includes_every_descendant_at_every_depth` · `a_child_cannot_be_hung_under_a_ticket_that_does_not_exist` |
| F-08 | Operator guidance to a running ticket is durable and reaches the next pick-up | `guidance_is_durable_and_comes_back_in_the_order_it_was_given` · `a_finished_ticket_takes_no_more_guidance` |
| F-09 | Approval is a distinct suspended state with one meaning | `a_phase_that_requires_approval_suspends_rather_than_running` · `approval_releases_the_phase_it_was_waiting_on_without_moving_the_position` · `a_phase_awaiting_approval_does_not_accept_a_completion_report` |

Fan-out is bounded at one by construction: phases run in declared order and there is no parallel
shape in this runtime yet, so F-06's fan-out bound cannot be exceeded rather than being enforced.

## Self-writing and storage amendments (S, ST)

Requirement identifiers from
09 — ADR sweep amendments.

| ID | Requirement | Guard |
|---|---|---|
| S-01 | Producers emit packages into a registry; no producer writes into the kernel tree | `a_produced_package_reaches_an_installation_only_by_being_published_into_a_registry` · `a_producer_cannot_write_into_the_kernel_tree` |
| S-02 | A produced package is inactive until a person activates it | `a_produced_package_arrives_installed_and_is_not_serving` · `a_producer_cannot_write_into_the_kernel_tree` |
| S-03 | Super-admin is a distinct, double-gated role; operator does not imply it | root is its own principal kind, and `transfer_root` takes a `Ctx<Confirmed>` and refuses anybody who is not root · `only_root_may_hand_root_over` (an administrator is refused) · `root_can_be_handed_over_and_never_taken_away` |
| S-04 | Kernel changes land through review; the platform proposes and never merges into itself | `a_producer_cannot_write_into_the_kernel_tree` (the refusal says a kernel change is a branch and a pull request) · `no_kernel_crate_can_start_a_process` (nothing in the kernel can run the tools a merge would need) |
| S-05 | An untrusted-code sandbox refuses unconfigured egress | `a_module_asking_for_an_import_nobody_offers_does_not_run_at_all` · `a_module_importing_network_sockets_is_refused_at_load_time` · `a_node_package_does_not_inherit_ambient_environment_variables` |
| S-06 | A change class is derived from the real changed paths, highest severity wins; a supplied class is a hint only | `the_most_severe_path_decides` · `a_hint_claiming_docs_does_not_move_a_change_that_touches_the_kernel` · `documentation_alone_is_docs_and_a_package_alone_is_a_package` · `anything_unrecognised_or_evasive_is_kernel` |
| S-07 | The self-repair and deploy runtime runs beside the kernel, never inside it | `no_kernel_crate_can_start_a_process`: restarting, deploying and rolling back all need a process the kernel cannot start, and the kernel's side is reading what that runtime reports (`DeployOutcome`, D-06) |
| S-08 | Outbound HTTPS requests pass an SSRF fence refusing non-public, loopback, and embedded IP ranges, redirects, and rebinding | `every_special_purpose_range_is_refused_and_a_public_address_is_admitted` · `an_address_embedded_in_an_ipv6_form_is_judged_by_the_address_inside_it` · `a_resolver_answer_mixing_public_and_private_addresses_is_refused` · `a_token_from_an_https_issuer_verifies_across_a_real_handshake` · `a_certificate_that_does_not_chain_to_the_trusted_roots_is_refused` · `a_certificate_for_another_name_is_refused` · `a_redirect_is_refused_and_where_it_pointed_is_never_asked` · `a_document_larger_than_the_ceiling_is_refused_rather_than_read_to_the_end` · `an_issuer_whose_keys_are_configured_signs_people_in_with_no_fetch_at_all` · `outbound_connections_are_opened_in_one_file` · `the_tls_client_lives_in_one_crate` · `the_artifact_cannot_build_a_fence_that_admits_this_machine` |
| ST-01 | A file write resolves to the person's chosen backend; the local fallback is quota-capped | `a_write_goes_to_the_backend_the_person_chose` · `a_chosen_backend_that_fails_refuses_rather_than_storing_elsewhere` · `the_local_fallback_is_capped_per_person_and_a_rewrite_counts_once` |
| ST-02 | A read-only handle is proven non-modifying by the engine, not by keyword inspection | `a_reading_session_is_read_only_because_the_engine_says_so_not_because_of_a_keyword` (a delete inside a statement that begins `WITH ... SELECT` is refused by PostgreSQL's privilege check) |
| ST-04 | Outbound notification is a governed rail: per-person topic routing, quiet hours, a transport registry, and sends and skips logged without throwing | `each_topic_goes_where_the_person_routed_it` · `quiet_hours_are_kept_across_midnight_and_the_skip_is_logged` · `a_broken_transport_or_a_missing_route_is_an_outcome_not_an_error` · `what_is_sent_is_scrubbed_and_what_is_logged_is_only_that_it_was` |
| ST-05 | Search is one caller-scoped rail over the person's own data through pluggable sources, never returning another person's rows | `search_is_one_rail_over_the_callers_own_data_and_never_returns_anyone_elses` |
| ST-03 | Row-level security coverage is machine-asserted table by table, with a justified exception list; stale or reason-less exceptions fail | `every_table_is_walled_or_named_with_a_reason`, against the database's own catalogue; the exception list is `store::RLS_EXCEPTIONS`, which is empty |

## Workflow defects from document 10

Document 10 lists fifteen defects in the current platform. Six are in the workflow area.

| Defect | Status |
|---|---|
| D1 — a manifest declares `phases` and nothing reads it | Cannot arise. There is one `WorkflowDef`; the runtime reads the declaration itself. |
| D2 — stages are vestigial | Cannot arise. No second execution shape exists. |
| D3 — the shape is declared twice and bridged by hand | Cannot arise. No bridge. |
| D4 — a graph without its definition degrades to a one-bot run | Refused at load: `a_definition_with_no_phases_cannot_load_so_it_cannot_degrade_to_one_phase` |
| D5 — `approval_required` means three different things | One meaning, three tests under F-09 above. |
| D6 — workflow position lives in three places | One field, one mapping function: the five `position::tests` · `a_ticket_walks_its_phases_and_every_move_leaves_a_row` |

A registry also refuses a package claiming a ticket type a built-in already holds:
`a_second_claim_on_a_ticket_type_fails_the_load_rather_than_replacing_the_first`.

## Build-level guards

| Rule | Guard |
|---|---|
| The objects crate never grows an I/O dependency | `the_objects_crate_never_grows_an_io_dependency` |
| An entry adapter cannot name an engine or the secret boundary | `an_entry_adapter_cannot_name_a_store_engine_or_the_secret_boundary` · `the_other_entry_adapters_cannot_name_an_engine` |
| The runtime does not depend on a transport or an engine | `the_runtime_does_not_depend_on_a_transport_or_an_engine` |
| The control plane depends on nothing above it | `the_control_plane_depends_on_nothing_above_it` |
| The secret boundary does not reach an engine | `the_secret_boundary_does_not_reach_an_engine` |
| A provider cannot reach a credential | `a_provider_cannot_reach_a_credential` |
| Delivery depends on no engine and on nothing it delivers to | `delivery_does_not_depend_on_an_engine_or_on_what_it_delivers_to` |
| The loader does not reach the secret boundary | `the_loader_does_not_reach_the_secret_boundary` |
| What a package compiles against names no kernel crate | `what_a_package_compiles_against_names_no_kernel_crate` |
| The node agent names no kernel crate | `the_node_agent_names_no_kernel_crate_either` |
| Only the composition root names every layer | `only_the_composition_root_names_every_layer` |
| No kernel crate can start a process | `no_kernel_crate_can_start_a_process` |
| The sign-in stack reaches no engine and no entry adapter | `the_sign_in_stack_reaches_no_engine_and_no_entry_adapter` |
| Trace assembly reads records and reaches no producer of them | `trace_assembly_reads_records_and_reaches_no_producer_of_them` |
| The connector framework cannot reach an engine or a transport | `the_connector_framework_cannot_reach_an_engine_or_a_transport` |
| The knowledge rail derives its scoping rather than inventing it | `the_knowledge_rail_derives_its_scoping_rather_than_inventing_it` |
| The time-series rail is a store of its own and reaches no other | `the_time_series_rail_is_a_store_of_its_own_and_reaches_no_other` |
| The person model holds records and reaches no subsystem | `the_person_model_holds_records_and_reaches_no_subsystem` |
| The kernel side of nodes reaches no engine and no entry adapter | `the_kernel_side_of_nodes_reaches_no_engine_and_no_entry_adapter` |
| Capture reaches memory only through the person model | `capture_reaches_memory_only_through_the_person_model_and_reaches_no_engine` |
| A producer cannot reach the loader it would need to activate its output | `a_producer_cannot_reach_the_loader_it_would_need_to_activate_its_own_output` |
| The optimiser reads finished runs and writes only through settings | `the_optimiser_reads_finished_runs_and_writes_only_through_settings` |
| Signature verification lives in exactly one crate | `the_token_verifier_is_the_only_crate_that_names_a_signature_library` |
| The no-spawn list is every crate but the stated exceptions | `the_crate_list_this_guard_checks_is_every_crate_except_the_agent_and_the_artifact` |
| No store reaches an upstream's key | `no_store_module_has_a_path_to_an_upstream_key` |
| This page claims only what a test holds | `the_headline_count_is_the_number_of_requirement_rows` · `every_test_a_claim_names_exists` |
