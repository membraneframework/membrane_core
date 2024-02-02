import sys, json;

full_json = json.load(sys.stdin)

try:
    project_items = full_json["items"]
    pr_url = sys.argv[1]
    [id] = [item["id"] for item in project_items if ("url" in item["content"] and item["content"]["url"] == pr_url)]
    print(id)
except:
    print("An exception occurred, provided JSON:")
    print(full_json)