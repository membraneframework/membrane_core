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
    print("An exception occurred, provided JSON:")
    print(membrane_team)
    print("provided PR_AUTHOR:", pr_author)