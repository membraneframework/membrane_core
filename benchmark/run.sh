echo "FEATURE BRANCH"
git checkout queue-buffers-when-auto-demand-is-low-v2
MIX_ENV=benchmark mix do deps.get, deps.compile --force --all, run benchmark/run.exs feature_branch_results


git stash push lib/
echo "MASTER BRANCH"
git checkout master
MIX_ENV=benchmark mix do deps.get, deps.compile --force --all, run benchmark/run.exs master_results

git checkout queue-buffers-when-auto-demand-is-low-v2
git stash apply

MIX_ENV=benchmark mix run benchmark/compare.exs feature_branch_results master_results

