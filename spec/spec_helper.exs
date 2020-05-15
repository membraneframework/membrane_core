# A hack to silence logs for testing, since ESpec doesn't allow capturing logs
Logger.remove_backend(:console)

ESpec.start()
