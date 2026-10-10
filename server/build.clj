(ns build
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/quizler-server.jar")

(defn uberjar [_]
  (let [basis (b/create-basis {:project "deps.edn"})]
    (b/delete {:path "target"})
    (b/copy-dir {:src-dirs ["src"] :target-dir class-dir})
    (b/compile-clj {:basis basis :ns-compile '[quizler.server] :class-dir class-dir})
    (b/uber {:class-dir class-dir :uber-file uber-file :basis basis
             :main 'quizler.server})))
