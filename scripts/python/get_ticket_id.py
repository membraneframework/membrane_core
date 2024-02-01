import sys, json;

project_items = json.load(sys.stdin)["items"]
pr_url = sys.argv[1]
[id] = [item["id"] for item in project_items if ("url" in item["content"] and item["content"]["url"] == pr_url)]
print(id)
