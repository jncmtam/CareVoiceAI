from app.integrations.vnpt.client import merge_conversation_events, parse_sse_json_events


def test_parse_sse_json_events_and_merge_card_text() -> None:
    raw = """
data:{"object":{"sb":{"card_data":[{"text":"Xin","type":"text"}],"card_data_info":{"status":1}}}}

data:{"object":{"sb":{"card_data":[{"text":" chào","type":"text"}],"card_data_info":{"status":2}}}}
"""
    events = parse_sse_json_events(raw)
    merged = merge_conversation_events(events)
    cards = merged["object"]["sb"]["card_data"]
    assert len(cards) == 2
    assert cards[0]["text"] == "Xin"
    assert cards[1]["text"] == " chào"