import sys, json;

full_json = json.load(sys.stdin)

pr_url = sys.argv[1]

project_items = full_json["items"]

item_id = None
for item in project_items:
    if "content" in item and "url" in item["content"]:
        if item["content"]["url"] == pr_url:
            item_id = item["id"]
            break

if item_id == None:
    print("Error occurred in get_ticket.py: item_id == None, provided JSON[items]: ", project_items)
    sys.exit(1)
else:
    print(item_id)