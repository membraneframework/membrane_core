import sys, json;

membrane_team = json.load(sys.stdin)
pr_author = sys.argv[1]

if pr_author == "membraneframeworkadmin":
  print("MEMBRANE")
  sys.exit(0)

try:
  for person in membrane_team:
    if person["login"] == pr_author:
      print("MEMBRANE")
      sys.exit(0)

  print("COMMUNITY")
except:
    print("An exception occurred in get_author_origin.py, provided JSON: ", membrane_team)
    print("Provided PR_AUTHOR: ", pr_author)
    sys.exit(1)
