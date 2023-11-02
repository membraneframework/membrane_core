import sys, json;

project_items = json.load(sys.stdin)["items"]
pr_url = sys.argv[1]
[id] = [item["id"] for item in project_items if item["content"]["url"] == pr_url]
print(id)
