(ns io.sshfling.validation.clojure-consumer
  (:import [io.sshfling.cli SSHFling]))

(defn -main [& args]
  (System/exit (SSHFling/run (into-array String args))))
