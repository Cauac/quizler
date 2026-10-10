(ns quizler.server
  (:require [org.httpkit.server :as http])
  (:gen-class))

(def port 8080)

(defn git-sha []
  (or (System/getenv "GIT_SHA") "unknown"))

(defn handler [{:keys [request-method uri]}]
  (cond
    (and (= request-method :get) (= uri "/"))
    {:status  200
     :headers {"Content-Type" "text/plain; charset=utf-8"}
     :body    (str "Hello from Quizler\nbuild: " (git-sha) "\n")}

    (and (= request-method :get) (= uri "/health"))
    {:status  200
     :headers {"Content-Type" "text/plain; charset=utf-8"}
     :body    "ok"}

    :else
    {:status  404
     :headers {"Content-Type" "text/plain; charset=utf-8"}
     :body    "not found"}))

(defn -main [& _]
  (let [server (http/run-server handler {:port port :legacy-return-value? false})]
    ;; server-stop! only signals the server and returns a promise; wait for it so the JVM
    ;; does not exit before in-flight requests are drained (ECS gives 30 s after SIGTERM).
    (.addShutdownHook (Runtime/getRuntime)
                      (Thread. ^Runnable
                       (fn []
                         (some-> (http/server-stop! server {:timeout 5000})
                                 (deref 10000 nil)))))
    (println "Quizler server listening on port" port "build" (git-sha))))
