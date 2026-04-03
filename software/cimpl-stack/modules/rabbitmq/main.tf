# Copyright 2026, Microsoft
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# RabbitMQ messaging broker
# Note: Istio sidecar disabled for RabbitMQ (requires NET_ADMIN/NET_RAW, blocked by AKS Automatic)

resource "kubernetes_secret_v1" "rabbitmq_credentials" {
  metadata {
    name      = "rabbitmq-credentials"
    namespace = var.namespace
  }

  data = {
    username      = var.rabbitmq_username
    password      = var.rabbitmq_password
    erlang-cookie = var.rabbitmq_erlang_cookie
  }
}

resource "kubectl_manifest" "rabbitmq_config" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: rabbitmq-config
      namespace: ${var.namespace}
    data:
      rabbitmq-env.conf: |
        USE_LONGNAME=true
      rabbitmq.conf: |
        cluster_formation.peer_discovery_backend = dns
        cluster_formation.dns.hostname = rabbitmq-headless.${var.namespace}.svc.cluster.local
        cluster_partition_handling = autoheal
        listeners.tcp.default = 5672
        management.tcp.port = 15672
        log.console = true
        log.console.level = info
        management.load_definitions = /etc/rabbitmq/definitions.json
      definitions.json: |
        {
          "vhosts": [
            {"name": "/"}
          ],
          "users": [
            {"name": "${var.rabbitmq_username}", "password": "${var.rabbitmq_password}", "tags": "administrator"}
          ],
          "permissions": [
            {"user": "${var.rabbitmq_username}", "vhost": "/", "configure": ".*", "write": ".*", "read": ".*"}
          ],
          "exchanges": [
            {"name": "legaltags", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "legaltagschanged", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "legaltagspublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "compliance-change--integration-test", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "recordstopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "recordstopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "recordschangedtopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "recordschangedtopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "schemachangedtopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "schemachangedtopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "indexing-progress", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "indexing-progresspublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "statuschangedtopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "statuschangedtopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "file-stagingarea-topic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "file-stagingarea-topicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "workflowrunevent", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "workflowruneventpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "datasettopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "datasettopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "registertopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "registertopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "registersubscription", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "registersubscriptionpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "notificationtopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "notificationtopicpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "legaltagschangedpublish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "legaltags-changed", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "legaltags-changed-publish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "records-changed", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "records-changed-publish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "records-changed-v2", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "records-changed-v2-publish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "schema-changed", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "schema-changed-publish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "status-changed", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "status-changed-publish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "indexing-progress-publish", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "replaytopic", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "replaytopicsubscription-exchange", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "notification-control", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "reprocess", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false},
            {"name": "reindex", "vhost": "/", "type": "fanout", "durable": true, "auto_delete": false}
          ],
          "queues": [
            {"name": "legaltags-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "legaltagschanged-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "legaltagspublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "compliance-change--integration-test-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "recordstopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "recordstopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "recordschangedtopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "recordschangedtopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "schemachangedtopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "schemachangedtopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexing-progress-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexing-progresspublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "statuschangedtopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "statuschangedtopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "file-stagingarea-topic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "file-stagingarea-topicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "workflowrunevent-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "workflowruneventpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "datasettopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "datasettopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "registertopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "registertopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "registersubscription-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "registersubscriptionpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notificationtopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notificationtopicpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "legaltagschangedpublish-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-legal", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-schema", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-storage", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-register", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-file", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-indexer", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-workflow", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-dataset", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-search", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-wellbore", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "storage-oqm-legaltags-changed", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "replaytopicsubscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "replaytopic-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "dead-lettering-replay-subscription", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexer-records-changed", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexer-schema-changed", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-control-sub", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-records-changed-service", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-records-changed-publish", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-legaltags-changed-service", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-legaltags-changed-publish", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-schema-changed-service", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-schema-changed-publish", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-status-changed-service", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-status-changed-publish", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-records-changed-v2-service", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "notification-records-changed-v2-publish", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexer-reprocess", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexer-reindex", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}},
            {"name": "indexer-records-changed-v2", "vhost": "/", "durable": true, "auto_delete": false, "arguments": {}}
          ],
          "bindings": [
            {"source": "legaltags", "vhost": "/", "destination": "legaltags-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "legaltagschanged", "vhost": "/", "destination": "legaltagschanged-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "legaltagspublish", "vhost": "/", "destination": "legaltagspublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "compliance-change--integration-test", "vhost": "/", "destination": "compliance-change--integration-test-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "recordstopic", "vhost": "/", "destination": "recordstopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "recordstopicpublish", "vhost": "/", "destination": "recordstopicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "recordschangedtopic", "vhost": "/", "destination": "recordschangedtopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "recordschangedtopicpublish", "vhost": "/", "destination": "recordschangedtopicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "schemachangedtopic", "vhost": "/", "destination": "schemachangedtopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "schemachangedtopicpublish", "vhost": "/", "destination": "schemachangedtopicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "indexing-progress", "vhost": "/", "destination": "indexing-progress-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "indexing-progresspublish", "vhost": "/", "destination": "indexing-progresspublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "statuschangedtopic", "vhost": "/", "destination": "statuschangedtopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "statuschangedtopicpublish", "vhost": "/", "destination": "statuschangedtopicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "file-stagingarea-topic", "vhost": "/", "destination": "file-stagingarea-topic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "file-stagingarea-topicpublish", "vhost": "/", "destination": "file-stagingarea-topicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "workflowrunevent", "vhost": "/", "destination": "workflowrunevent-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "workflowruneventpublish", "vhost": "/", "destination": "workflowruneventpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "datasettopic", "vhost": "/", "destination": "datasettopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "datasettopicpublish", "vhost": "/", "destination": "datasettopicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "registertopic", "vhost": "/", "destination": "registertopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "registertopicpublish", "vhost": "/", "destination": "registertopicpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "registersubscription", "vhost": "/", "destination": "registersubscription-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "registersubscriptionpublish", "vhost": "/", "destination": "registersubscriptionpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "notificationtopic", "vhost": "/", "destination": "notificationtopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "legaltagschangedpublish", "vhost": "/", "destination": "legaltagschangedpublish-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "legaltags-changed", "vhost": "/", "destination": "storage-oqm-legaltags-changed", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "replaytopic", "vhost": "/", "destination": "replaytopicsubscription", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "replaytopic", "vhost": "/", "destination": "replaytopic-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "replaytopicsubscription-exchange", "vhost": "/", "destination": "dead-lettering-replay-subscription", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "records-changed", "vhost": "/", "destination": "indexer-records-changed", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "schema-changed", "vhost": "/", "destination": "indexer-schema-changed", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "notification-control", "vhost": "/", "destination": "notification-control-sub", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "records-changed", "vhost": "/", "destination": "notification-records-changed-service", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "records-changed-publish", "vhost": "/", "destination": "notification-records-changed-publish", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "legaltags-changed", "vhost": "/", "destination": "notification-legaltags-changed-service", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "legaltags-changed-publish", "vhost": "/", "destination": "notification-legaltags-changed-publish", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "schema-changed", "vhost": "/", "destination": "notification-schema-changed-service", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "schema-changed-publish", "vhost": "/", "destination": "notification-schema-changed-publish", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "status-changed", "vhost": "/", "destination": "notification-status-changed-service", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "status-changed-publish", "vhost": "/", "destination": "notification-status-changed-publish", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "records-changed-v2", "vhost": "/", "destination": "notification-records-changed-v2-service", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "records-changed-v2-publish", "vhost": "/", "destination": "notification-records-changed-v2-publish", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "reprocess", "vhost": "/", "destination": "indexer-reprocess", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "reindex", "vhost": "/", "destination": "indexer-reindex", "destination_type": "queue", "routing_key": "", "arguments": {}},
            {"source": "records-changed-v2", "vhost": "/", "destination": "indexer-records-changed-v2", "destination_type": "queue", "routing_key": "", "arguments": {}}
          ]
        }
      enabled_plugins: |
        [rabbitmq_peer_discovery_common,rabbitmq_management,rabbitmq_prometheus].
  YAML
}

resource "kubectl_manifest" "rabbitmq_headless_service" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: rabbitmq-headless
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: rabbitmq
    spec:
      type: ClusterIP
      clusterIP: None
      publishNotReadyAddresses: true
      selector:
        app.kubernetes.io/name: rabbitmq
      ports:
        - name: amqp
          port: 5672
          targetPort: amqp
        - name: epmd
          port: 4369
          targetPort: epmd
        - name: dist
          port: 25672
          targetPort: dist
        - name: http-stats
          port: 15672
          targetPort: stats
  YAML
}

resource "kubectl_manifest" "rabbitmq_client_service" {
  yaml_body = <<-YAML
    apiVersion: v1
    kind: Service
    metadata:
      name: rabbitmq
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: rabbitmq
    spec:
      type: ClusterIP
      selector:
        app.kubernetes.io/name: rabbitmq
        rabbitmq.service/variant: client
      ports:
        - name: amqp
          port: 5672
          targetPort: amqp
        - name: http-stats
          port: 15672
          targetPort: stats
  YAML
}

resource "kubectl_manifest" "rabbitmq_statefulset" {
  yaml_body = <<-YAML
    apiVersion: apps/v1
    kind: StatefulSet
    metadata:
      name: rabbitmq
      namespace: ${var.namespace}
      labels:
        app.kubernetes.io/name: rabbitmq
    spec:
      serviceName: rabbitmq-headless
      replicas: 3
      podManagementPolicy: OrderedReady
      selector:
        matchLabels:
          app.kubernetes.io/name: rabbitmq
      template:
        metadata:
          labels:
            app.kubernetes.io/name: rabbitmq
            rabbitmq.service/variant: client
          annotations:
            sidecar.istio.io/inject: "false"
        spec:
          enableServiceLinks: false
          securityContext:
            runAsUser: 999
            runAsGroup: 999
            fsGroup: 999
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          tolerations:
            - effect: NoSchedule
              key: workload
              value: "${var.nodepool_name}"
          affinity:
            nodeAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                nodeSelectorTerms:
                  - matchExpressions:
                      - key: agentpool
                        operator: In
                        values:
                          - ${var.nodepool_name}
          topologySpreadConstraints:
            - maxSkew: 1
              topologyKey: topology.kubernetes.io/zone
              whenUnsatisfiable: ScheduleAnyway
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: rabbitmq
            - maxSkew: 1
              topologyKey: kubernetes.io/hostname
              whenUnsatisfiable: ScheduleAnyway
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: rabbitmq
          containers:
            - name: rabbitmq
              image: rabbitmq:4.1.0-management-alpine
              command: ["sh", "-c"]
              args:
                - |
                  echo "$RABBITMQ_ERLANG_COOKIE" > /var/lib/rabbitmq/.erlang.cookie
                  chmod 600 /var/lib/rabbitmq/.erlang.cookie
                  exec docker-entrypoint.sh rabbitmq-server
              ports:
                - containerPort: 5672
                  name: amqp
                - containerPort: 15672
                  name: stats
                - containerPort: 4369
                  name: epmd
                - containerPort: 25672
                  name: dist
              env:
                - name: RABBITMQ_DEFAULT_USER
                  valueFrom:
                    secretKeyRef:
                      name: rabbitmq-credentials
                      key: username
                - name: RABBITMQ_DEFAULT_PASS
                  valueFrom:
                    secretKeyRef:
                      name: rabbitmq-credentials
                      key: password
                - name: RABBITMQ_ERLANG_COOKIE
                  valueFrom:
                    secretKeyRef:
                      name: rabbitmq-credentials
                      key: erlang-cookie
                - name: RABBITMQ_USE_LONGNAME
                  value: "true"
                - name: MY_POD_NAME
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.name
                - name: RABBITMQ_NODENAME
                  value: "rabbit@$(MY_POD_NAME).rabbitmq-headless.${var.namespace}.svc.cluster.local"
              volumeMounts:
                - name: data
                  mountPath: /var/lib/rabbitmq
                - name: env-config
                  mountPath: /etc/rabbitmq/rabbitmq-env.conf
                  subPath: rabbitmq-env.conf
                - name: config
                  mountPath: /etc/rabbitmq/conf.d/10-custom.conf
                  subPath: rabbitmq.conf
                - name: plugins
                  mountPath: /etc/rabbitmq/enabled_plugins
                  subPath: enabled_plugins
                - name: definitions
                  mountPath: /etc/rabbitmq/definitions.json
                  subPath: definitions.json
              resources:
                requests:
                  cpu: 250m
                  memory: 512Mi
                limits:
                  cpu: "1"
                  memory: 1Gi
              livenessProbe:
                exec:
                  command: ["rabbitmq-diagnostics", "status"]
                initialDelaySeconds: 120
                periodSeconds: 30
                timeoutSeconds: 10
                failureThreshold: 6
              readinessProbe:
                exec:
                  command: ["rabbitmq-diagnostics", "check_port_connectivity"]
                initialDelaySeconds: 20
                periodSeconds: 10
                timeoutSeconds: 10
                failureThreshold: 6
              securityContext:
                allowPrivilegeEscalation: false
                capabilities:
                  drop: ["ALL"]
                runAsNonRoot: true
                seccompProfile:
                  type: RuntimeDefault
          volumes:
            - name: env-config
              configMap:
                name: rabbitmq-config
            - name: config
              configMap:
                name: rabbitmq-config
            - name: plugins
              configMap:
                name: rabbitmq-config
            - name: definitions
              configMap:
                name: rabbitmq-config
      volumeClaimTemplates:
        - metadata:
            name: data
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: rabbitmq-storageclass
            resources:
              requests:
                storage: 8Gi
  YAML

  depends_on = [
    kubernetes_secret_v1.rabbitmq_credentials,
    kubectl_manifest.rabbitmq_config,
    kubectl_manifest.rabbitmq_headless_service,
    kubectl_manifest.rabbitmq_client_service
  ]
}
