#!/usr/bin/env python3
"""Convert n8n workflow HTTP Request nodes (Supabase REST) to Postgres nodes.
Eliminates SUPABASE_SERVICE_ROLE from followup, seed, and inbound workflows."""
import json, copy, os

PG_CRED = {"postgres": {"id": "ADMIN_DB_CREDENTIAL_ID", "name": "Admin DB"}}

def pg(node_id, name, query, position, cont_fail=False, on_error=None):
    n = {
        "parameters": {"operation": "executeQuery", "query": query},
        "id": node_id, "name": name,
        "type": "n8n-nodes-base.postgres", "typeVersion": 2.5,
        "position": position,
        "credentials": copy.deepcopy(PG_CRED)
    }
    if cont_fail:
        n["continueOnFail"] = True
    if on_error:
        n["onError"] = on_error
    return n


def convert_followup():
    with open("wf-followup-v2.json") as f:
        wf = json.load(f)

    QUERIES = {
        "fu-fetch": {
            "q": (
                "SELECT id, name, email, phone, company, status, attempt_count, "
                "last_channel, conversation_stage, source\n"
                "FROM outreach_leads\n"
                "WHERE status = 'CONTACTED'\n"
                "  AND next_followup_at <= NOW()\n"
                "ORDER BY next_followup_at ASC\n"
                "LIMIT 100"
            ),
            "on_error": "stopWorkflow"
        },
        "fu-mark-cold": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET status = 'COLD',\n"
                "    next_followup_at = NULL,\n"
                "    lost_reason = 'max_followups_exhausted',\n"
                "    updated_at = NOW()\n"
                "WHERE id = '{{ $json.id }}'\n"
                "RETURNING id"
            ),
            "on_error": "stopWorkflow"
        },
        "fu-log-cold": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, message_text, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Compute FU Number\"].json.id }}',\n"
                "  'SYSTEM', 'MARKED_COLD', 'OUTBOUND',\n"
                "  {{ $node[\"Compute FU Number\"].json.fu_number }},\n"
                "  'Max follow-ups reached, marked COLD',\n"
                "  'processed'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        },
        "fu-update-ok": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET attempt_count = {{ $node[\"Compute FU Number\"].json.fu_number }},\n"
                "    last_channel = 'WHATSAPP',\n"
                "    last_contacted_at = NOW(),\n"
                "    next_followup_at = NOW() + "
                "({{ $node[\"Compute FU Number\"].json.next_delay_days }} * INTERVAL '1 day'),\n"
                "    updated_at = NOW()\n"
                "WHERE id = '{{ $node[\"Compute FU Number\"].json.id }}'\n"
                "RETURNING id"
            ),
            "on_error": "stopWorkflow"
        },
        "fu-log-ok": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, message_text, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Compute FU Number\"].json.id }}',\n"
                "  'WHATSAPP', 'FU_SENT', 'OUTBOUND',\n"
                "  {{ $node[\"Compute FU Number\"].json.fu_number }},\n"
                "  '[TEMPLATE] ' || '{{ $node[\"Compute FU Number\"].json.template_name }}',\n"
                "  'processed'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        },
        "fu-log-fail": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, error_message, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Compute FU Number\"].json.id }}',\n"
                "  'WHATSAPP', 'FU_FAILED', 'OUTBOUND',\n"
                "  {{ $node[\"Compute FU Number\"].json.fu_number }},\n"
                "  'WA follow-up send failed',\n"
                "  'error'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        }
    }

    new_nodes = []
    for node in wf["nodes"]:
        nid = node["id"]
        if nid in QUERIES:
            q = QUERIES[nid]
            new_nodes.append(pg(nid, node["name"], q["q"], node["position"],
                               cont_fail=q.get("cont_fail", False),
                               on_error=q.get("on_error")))
            print(f"  [FU] {node['name']} -> postgres")
        else:
            new_nodes.append(node)

    wf["nodes"] = new_nodes
    wf["versionId"] = "fu-v2-002-pg"
    with open("wf-followup-v2.json", "w") as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print("  FOLLOWUP done\n")


def convert_seed():
    with open("wf-seed-v2.json") as f:
        wf = json.load(f)

    QUERIES = {
        "seed-fetch": {
            "q": (
                "SELECT id, name, email, phone, source, category, "
                "last_channel, web, builder_url, store_slug\n"
                "FROM outreach_leads\n"
                "WHERE status = 'NEW'\n"
                "ORDER BY created_at ASC\n"
                "LIMIT 50"
            ),
            "on_error": "stopWorkflow"
        },
        "seed-update-wa-ok": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET status = 'CONTACTED',\n"
                "    last_channel = 'WHATSAPP',\n"
                "    last_contacted_at = NOW(),\n"
                "    attempt_count = 1,\n"
                "    next_followup_at = NOW() + INTERVAL '3 days',\n"
                "    updated_at = NOW()\n"
                "WHERE id = '{{ $node[\"Validate Contact\"].json.id }}'\n"
                "RETURNING id"
            ),
            "on_error": "stopWorkflow"
        },
        "seed-log-wa-ok": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, wamid, message_text, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Validate Contact\"].json.id }}',\n"
                "  'WHATSAPP', 'SEED_SENT', 'OUTBOUND', 1,\n"
                "  '{{ $node[\"Send WA Seed\"].json.messages[0].id }}',\n"
                "  '[TEMPLATE] novavision_primer_contacto_qr_v1',\n"
                "  'processed'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        },
        "seed-log-wa-fail": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, error_message, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Validate Contact\"].json.id }}',\n"
                "  'WHATSAPP', 'SEED_FAILED', 'OUTBOUND', 1,\n"
                "  'WA send failed',\n"
                "  'error'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        },
        "seed-update-email-ok": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET status = 'CONTACTED',\n"
                "    last_channel = 'EMAIL',\n"
                "    last_contacted_at = NOW(),\n"
                "    attempt_count = 1,\n"
                "    next_followup_at = NOW() + INTERVAL '3 days',\n"
                "    updated_at = NOW()\n"
                "WHERE id = '{{ $node[\"Validate Contact\"].json.id }}'\n"
                "RETURNING id"
            ),
            "on_error": "stopWorkflow"
        },
        "seed-log-email-ok": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, message_text, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Validate Contact\"].json.id }}',\n"
                "  'EMAIL', 'SEED_SENT', 'OUTBOUND', 1,\n"
                "  '[EMAIL] Seed intro',\n"
                "  'processed'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        },
        "seed-log-email-fail": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, attempt, error_message, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Validate Contact\"].json.id }}',\n"
                "  'EMAIL', 'SEED_FAILED', 'OUTBOUND', 1,\n"
                "  'Email send failed',\n"
                "  'error'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        }
    }

    new_nodes = []
    for node in wf["nodes"]:
        nid = node["id"]
        if nid in QUERIES:
            q = QUERIES[nid]
            new_nodes.append(pg(nid, node["name"], q["q"], node["position"],
                               cont_fail=q.get("cont_fail", False),
                               on_error=q.get("on_error")))
            print(f"  [SEED] {node['name']} -> postgres")
        else:
            new_nodes.append(node)

    wf["nodes"] = new_nodes
    wf["versionId"] = "seed-v2-002-pg"
    with open("wf-seed-v2.json", "w") as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print("  SEED done\n")


def convert_inbound():
    with open("wf-inbound-v2.json") as f:
        wf = json.load(f)

    # --- Also need to update the Check Opt-out Code node to use $node refs ---
    # --- And the dedup check to always return 1 row ---
    # --- And the Lead Found Check to handle Postgres output ---

    QUERIES = {
        "inbound-check-dedup": {
            "q": (
                "SELECT EXISTS(\n"
                "  SELECT 1 FROM outreach_logs\n"
                "  WHERE wamid = '{{ $node[\"Parse WA Message\"].json.wamid }}'\n"
                "  LIMIT 1\n"
                ") as is_duplicate"
            )
        },
        "inbound-mark-lost": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET status = 'LOST',\n"
                "    lost_at = NOW(),\n"
                "    lost_reason = 'opt_out',\n"
                "    bot_enabled = false,\n"
                "    next_followup_at = NULL,\n"
                "    updated_at = NOW()\n"
                "WHERE phone = '{{ $node[\"Check Opt-out\"].json.from }}'\n"
                "RETURNING id"
            ),
            "on_error": "stopWorkflow"
        },
        "inbound-find-lead": {
            "q": (
                "SELECT l.id, l.name, l.email, l.phone, l.company, l.status,\n"
                "       l.conversation_stage, l.attempt_count, l.ai_state,\n"
                "       l.bot_enabled, l.hot_lead, l.ai_engagement_score,\n"
                "       l.account_id, l.onboarding_status,\n"
                "       CASE WHEN l.id IS NOT NULL THEN true ELSE false END as lead_found\n"
                "FROM (SELECT 1) dummy\n"
                "LEFT JOIN outreach_leads l ON l.phone = '{{ $node[\"Check Opt-out\"].json.from }}'\n"
                "LIMIT 1"
            )
        },
        "inbound-update-lead": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET status = 'IN_CONVERSATION',\n"
                "    last_channel = 'WHATSAPP',\n"
                "    last_contacted_at = NOW(),\n"
                "    updated_at = NOW()\n"
                "WHERE id = '{{ $json.id }}'\n"
                "RETURNING *"
            )
        },
        "inbound-create-lead": {
            "q": (
                "INSERT INTO outreach_leads "
                "(name, phone, status, source, conversation_stage, last_channel, "
                "last_contacted_at, attempt_count, bot_enabled)\n"
                "VALUES (\n"
                "  '{{ $node[\"Check Opt-out\"].json.contact_name || \"Desconocido\" }}',\n"
                "  '{{ $node[\"Check Opt-out\"].json.from }}',\n"
                "  'IN_CONVERSATION', 'INBOUND_WA', 'INTRO', 'WHATSAPP',\n"
                "  NOW(), 0, true\n"
                ")\n"
                "ON CONFLICT (phone) DO UPDATE SET\n"
                "  status = 'IN_CONVERSATION',\n"
                "  last_channel = 'WHATSAPP',\n"
                "  last_contacted_at = NOW(),\n"
                "  updated_at = NOW()\n"
                "RETURNING *"
            )
        },
        "inbound-log-msg": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, wamid, msg_type, "
                "from_name, from_phone, message_text, processing_status)\n"
                "VALUES (\n"
                "  '{{ $json.id }}',\n"
                "  'WHATSAPP', 'INBOUND_MSG', 'INBOUND',\n"
                "  '{{ $node[\"Check Opt-out\"].json.wamid }}',\n"
                "  '{{ $node[\"Check Opt-out\"].json.msg_type }}',\n"
                "  '{{ $node[\"Check Opt-out\"].json.contact_name }}',\n"
                "  '{{ $node[\"Check Opt-out\"].json.from }}',\n"
                "  '{{ $node[\"Check Opt-out\"].json.text }}',\n"
                "  'processed'\n"
                ")\nRETURNING id, lead_id"
            ),
            "cont_fail": True
        },
        "inbound-get-history": {
            "q": (
                "SELECT direction, message_text, created_at\n"
                "FROM outreach_logs\n"
                "WHERE lead_id = '{{ $json.lead_id }}'\n"
                "ORDER BY created_at DESC\n"
                "LIMIT 10"
            )
        },
        "inbound-get-playbook": {
            "q": (
                "SELECT key, segment, stage, type, title, content, priority, topic\n"
                "FROM nv_playbook\n"
                "WHERE active = true\n"
                "ORDER BY priority ASC"
            )
        },
        "inbound-fetch-coupon-config": {
            "q": (
                "SELECT key, value\n"
                "FROM outreach_config\n"
                "WHERE key IN ('coupon_enabled', 'coupon_offer_stage', "
                "'coupon_default_code', 'coupon_offer_message')"
            )
        },
        "inbound-fetch-active-coupons": {
            "q": (
                "SELECT id, code, description, discount_type, discount_value, "
                "valid_until, max_uses, current_uses\n"
                "FROM outreach_coupons\n"
                "WHERE active = true\n"
                "ORDER BY created_at ASC\n"
                "LIMIT 5"
            )
        },
        "inbound-log-coupon-offer": {
            "q": (
                "INSERT INTO outreach_coupon_offers (lead_id, coupon_id)\n"
                "VALUES (\n"
                "  '{{ $json.lead_id }}',\n"
                "  '{{ $json.coupon_id }}'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        },
        "inbound-update-intel": {
            "q": (
                "UPDATE outreach_leads\n"
                "SET ai_engagement_score = {{ $json.new_score }},\n"
                "    conversation_stage = '{{ $json.new_stage || "
                "$node[\"Prepare AI Context\"].json.conversation_stage }}',\n"
                "    hot_lead = {{ $json.is_hot }},\n"
                "    updated_at = NOW()\n"
                "WHERE id = '{{ $json.lead_id }}'\n"
                "RETURNING id"
            )
        },
        "inbound-log-reply": {
            "q": (
                "INSERT INTO outreach_logs "
                "(lead_id, channel, action, direction, wamid, message_text, "
                "ai_state, processing_status)\n"
                "VALUES (\n"
                "  '{{ $node[\"Post-process AI\"].json.lead_id }}',\n"
                "  'WHATSAPP', 'BOT_REPLY', 'BOT',\n"
                "  COALESCE('{{ $json.messages[0].id }}', ''),\n"
                "  '{{ $node[\"Post-process AI\"].json.reply }}',\n"
                "  '{{ JSON.stringify({ intent: $node[\"Post-process AI\"].json.intent, "
                "score: $node[\"Post-process AI\"].json.new_score, "
                "stage: $node[\"Post-process AI\"].json.new_stage, "
                "reasoning: $node[\"Post-process AI\"].json.reasoning, "
                "coupon_offered: $node[\"Post-process AI\"].json.coupon_code_offered }) }}',\n"
                "  'processed'\n"
                ")\nRETURNING id"
            ),
            "cont_fail": True
        }
    }

    # --- Update code nodes for proper $node references ---
    CODE_UPDATES = {
        "inbound-check-optout": (
            "const text = ($node['Parse WA Message'].json.text || '').toLowerCase().trim();\n"
            "const OPT_OUT = ['stop','parar','basta','no más','no mas',\n"
            "  'cancelar suscripción','cancelar suscripcion','dejar de recibir',\n"
            "  'no me escriban','borrame','eliminarme','desuscribirme'];\n"
            "\n"
            "const isOptOut = OPT_OUT.some(kw => text.includes(kw));\n"
            "const parsed = $node['Parse WA Message'].json;\n"
            "return [{ json: { ...parsed, is_opt_out: isOptOut } }];"
        ),
        "inbound-lead-check": (
            "const row = $input.first().json;\n"
            "const inboundData = $node['Check Opt-out'].json;\n"
            "\n"
            "if (row && row.lead_found === true && row.id) {\n"
            "  return [{\n"
            "    json: {\n"
            "      lead_found: true,\n"
            "      lead: row,\n"
            "      ...inboundData\n"
            "    }\n"
            "  }];\n"
            "} else {\n"
            "  return [{\n"
            "    json: {\n"
            "      lead_found: false,\n"
            "      lead: null,\n"
            "      ...inboundData\n"
            "    }\n"
            "  }];\n"
            "}"
        )
    }

    # Also update "Already Processed?" IF to check is_duplicate instead of array
    IF_UPDATES = {
        "inbound-is-dup": {
            "conditions": {
                "options": {},
                "conditions": [
                    {
                        "id": "is-dup",
                        "leftValue": "={{$json.is_duplicate}}",
                        "rightValue": True,
                        "operator": {"type": "boolean", "operation": "equals"}
                    }
                ]
            }
        },
        "inbound-lead-found-if": {
            "conditions": {
                "options": {},
                "conditions": [
                    {
                        "id": "lead-found",
                        "leftValue": "={{$json.lead_found}}",
                        "rightValue": True,
                        "operator": {"type": "boolean", "operation": "equals"}
                    }
                ]
            }
        }
    }

    new_nodes = []
    for node in wf["nodes"]:
        nid = node["id"]
        if nid in QUERIES:
            q = QUERIES[nid]
            new_nodes.append(pg(nid, node["name"], q["q"], node["position"],
                               cont_fail=q.get("cont_fail", False),
                               on_error=q.get("on_error")))
            print(f"  [IN] {node['name']} -> postgres")
        elif nid in CODE_UPDATES:
            node["parameters"]["jsCode"] = CODE_UPDATES[nid]
            new_nodes.append(node)
            print(f"  [IN] {node['name']} -> code updated")
        elif nid in IF_UPDATES:
            node["parameters"]["conditions"] = IF_UPDATES[nid]["conditions"]
            new_nodes.append(node)
            print(f"  [IN] {node['name']} -> IF updated")
        else:
            new_nodes.append(node)

    wf["nodes"] = new_nodes
    wf["versionId"] = "inbound-v2-003-pg"
    with open("wf-inbound-v2.json", "w") as f:
        json.dump(wf, f, indent=2, ensure_ascii=False)
    print("  INBOUND done\n")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    print("=== Converting workflows to Postgres (no SUPABASE_SERVICE_ROLE) ===\n")
    convert_followup()
    convert_seed()
    convert_inbound()

    # Verify
    import subprocess
    for f in ["wf-followup-v2.json", "wf-seed-v2.json", "wf-inbound-v2.json"]:
        count = subprocess.run(["grep", "-c", "SUPABASE_SERVICE_ROLE", f],
                               capture_output=True, text=True)
        c = count.stdout.strip()
        status = "OK" if c == "0" else f"FAIL ({c} refs remaining)"
        print(f"  {f}: {status}")

    # Cleanup
    print("\nDone!")
