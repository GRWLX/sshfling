(import ../src/sshfling/init :as sshfling)

(def smoke (get (dyn :args) 1))
(assert smoke "The consumer requires a smoke-project path")
(assert (= 0 (sshfling/run ["--version"])))
(assert (= 0 (sshfling/run ["init" smoke "--force" "--session-seconds" "60"])))
(assert (os/stat (string smoke "/production/sshfling-session")))
