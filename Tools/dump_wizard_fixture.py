#!/usr/bin/env python3
"""Read-only dump of the hand-built `scooter_journey` wizard fixture.

The fixture is authored in the Ad Manager UI, not by the Go mock seed, so it is
the only thing in the suite that can catch a platform-writes / engine-reads shape
mismatch (adhub #2459, #2483). It also does not survive `make db-reset`. This
records the shape it was in when the E2E wizard-parity group passed.

Talks to the local libSQL HTTP endpoint only; issues SELECTs exclusively.
"""

import json
import sys
import urllib.request

ENDPOINT = "http://127.0.0.1:8081/v2/pipeline"
DEFINITION_KEY = "scooter_journey"


def query(sql):
    payload = json.dumps(
        {"requests": [{"type": "execute", "stmt": {"sql": sql}}, {"type": "close"}]}
    ).encode()
    req = urllib.request.Request(
        ENDPOINT, data=payload, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        body = json.load(resp)
    result = body["results"][0]
    if "response" not in result:
        raise RuntimeError(f"query failed: {sql}\n{json.dumps(result)[:400]}")
    res = result["response"]["result"]
    cols = [c["name"] for c in res["cols"]]
    return [{c: cell.get("value") for c, cell in zip(cols, row)} for row in res["rows"]]


def one(sql):
    rows = query(sql)
    return rows[0] if rows else None


# Every query is scoped to the definition by key, so the dump can never bleed
# rows belonging to the seeded demo/e2e journeys.
DEF = f"(SELECT id FROM journey_definitions WHERE key = '{DEFINITION_KEY}')"
DEALS = f"(SELECT id FROM journey_deals WHERE journey_definition_id = {DEF})"
STAGES = f"(SELECT id FROM journey_stages WHERE journey_definition_id = {DEF})"
NODES = f"(SELECT id FROM journey_stage_nodes WHERE journey_stage_id IN {STAGES})"
CREATIVES = f"(SELECT id FROM journey_stage_creatives WHERE journey_deal_id IN {DEALS})"

QUERIES = {
    "journey_definitions": f"SELECT * FROM journey_definitions WHERE id = {DEF}",
    "journey_deals": f"SELECT * FROM journey_deals WHERE journey_definition_id = {DEF}",
    "journey_deal_locales": f"SELECT * FROM journey_deal_locales WHERE journey_deal_id IN {DEALS}",
    "journey_deal_stage_settings": f"SELECT * FROM journey_deal_stage_settings WHERE journey_deal_id IN {DEALS}",
    "journey_deal_node_tracked_events": f"SELECT * FROM journey_deal_node_tracked_events WHERE journey_deal_id IN {DEALS}",
    "journey_deal_stage_node_video_settings": f"SELECT * FROM journey_deal_stage_node_video_settings WHERE journey_deal_id IN {DEALS}",
    "journey_deal_stage_node_pricing_overrides": f"SELECT * FROM journey_deal_stage_node_pricing_overrides WHERE journey_deal_id IN {DEALS}",
    "journey_deal_verifications": f"SELECT * FROM journey_deal_verifications WHERE journey_deal_id IN {DEALS}",
    "journey_stage_event_map": f"SELECT * FROM journey_stage_event_map WHERE journey_deal_id IN {DEALS}",
    "journey_stages": f"SELECT * FROM journey_stages WHERE journey_definition_id = {DEF} ORDER BY sort_order",
    "journey_stage_nodes": f"SELECT * FROM journey_stage_nodes WHERE journey_stage_id IN {STAGES}",
    "journey_stage_node_styles": f"SELECT * FROM journey_stage_node_styles WHERE journey_stage_node_id IN {NODES}",
    "journey_stage_creatives": f"SELECT * FROM journey_stage_creatives WHERE journey_deal_id IN {DEALS}",
    "journey_stage_creative_verifications": f"SELECT * FROM journey_stage_creative_verifications WHERE journey_stage_creative_id IN {CREATIVES}",
}

# The creative contents are joined to their template field so the snapshot records
# the field KEYS the wizard wrote. Those keys are the #2483 seam: the platform
# writes camelCase (destinationUrl, urlSlide1..3) and the click resolver has to
# match them, so a snapshot without the keys would lose the point of the fixture.
CONTENTS_SQL = f"""
SELECT c.id, c.journey_stage_creative_id, c.locale, c.value, c.status,
       f.key AS template_field_key, f.type AS template_field_type
FROM journey_stage_creative_contents c
LEFT JOIN template_fields f ON c.template_field_id = f.id
WHERE c.journey_stage_creative_id IN {CREATIVES}
"""

# Node bindings: which placement/template each node sits on. Without these the
# fixture is not rebuildable (and picking the wrong placement lets another active
# journey deal mask it).
NODE_BINDINGS_SQL = f"""
SELECT n.public_id AS node_public_id, s.key AS stage_key, s.sort_order,
       p.key AS placement_key, t.key AS template_key, n.status
FROM journey_stage_nodes n
JOIN journey_stages s ON n.journey_stage_id = s.id
LEFT JOIN placements p ON n.placement_id = p.id
LEFT JOIN templates t ON n.template_id = t.id
WHERE s.journey_definition_id = {DEF}
ORDER BY s.sort_order
"""


def main():
    if one(f"SELECT id FROM journey_definitions WHERE key = '{DEFINITION_KEY}'") is None:
        print(f"FATAL: definition {DEFINITION_KEY!r} is not present", file=sys.stderr)
        return 2

    tables = {name: query(sql) for name, sql in QUERIES.items()}
    tables["journey_stage_creative_contents"] = query(CONTENTS_SQL)
    bindings = query(NODE_BINDINGS_SQL)

    deal = tables["journey_deals"][0] if tables["journey_deals"] else {}
    out = {
        "_comment": (
            "Read-only snapshot of the hand-built wizard fixture driving the "
            "Journey E2E wizard-parity group (K1-K4). Authored in the Ad Manager "
            "UI, NOT by the Go mock seed - which is exactly what lets it catch a "
            "platform-writes/engine-reads shape mismatch (adhub #2459, #2483). "
            "`make db-reset` destroys it and the K scenarios then SKIP with no "
            "failure to signal it. See README.md in this directory to rebuild."
        ),
        "capturedFrom": {
            "endpoint": ENDPOINT,
            "definitionKey": DEFINITION_KEY,
            "dealPublicId": deal.get("public_id"),
        },
        "summary": {
            "stageOrder": [s.get("key") for s in tables["journey_stages"]],
            "nodeBindings": bindings,
            "pricing": deal.get("default_pricing_mode"),
            "fallbackBehaviour": deal.get("fallback_behaviour"),
            "completionStrategy": deal.get("completion_strategy"),
            "dealStatus": deal.get("status"),
            "templateFieldKeys": sorted(
                {
                    c["template_field_key"]
                    for c in tables["journey_stage_creative_contents"]
                    if c.get("template_field_key")
                }
            ),
        },
        "tables": {name: rows for name, rows in sorted(tables.items()) if rows},
    }
    json.dump(out, sys.stdout, indent=2, sort_keys=True)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
