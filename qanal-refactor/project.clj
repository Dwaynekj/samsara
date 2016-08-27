(defproject samsara/qanal (-> "../samsara.version" slurp .trim)
  :description "An Application that bulk indexes docs from Kafka to Elasticsearch"

  :url "http://samsara-analytics.io/"

  :scm {:name "github"
        :url "https://github.com/samsara/samsara/tree/master/qanal"}

  :license {:name "Apache License 2.0"
            :url "http://www.apache.org/licenses/LICENSE-2.0"}

  :dependencies [[org.clojure/clojure "1.8.0"]
                 [com.brunobonacci/safely "0.2.1"]]

  :main qanal.core

  :profiles {:uberjar {:aot :all}
             :dev {:dependencies [[midje "1.7.0"]
                                  [midje-junit-formatter "0.1.0-SNAPSHOT"]]
                   :plugins [[lein-midje "3.1.3"]
                             [lein-bin "0.3.5"]
                             [lein-shell "0.5.0"]]}}

  :aliases {"docker"
            ["shell" "docker" "build" "-t" "samsara/qanal:${:version}" "."]

            "docker-latest"
            ["shell" "docker" "build" "-t" "samsara/qanal" "."]}

  :jvm-opts ["-server" "-Dfile.encoding=utf-8"]
  :bin {:name "qanal" :bootclasspath false}
  )