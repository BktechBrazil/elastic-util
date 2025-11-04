APP_NS=customer-elasticsearch
ES_NAME=customer-cluster-elastic
OP_NS=openshift-operators
OUT="eck-diag-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

# ---- Definições e status dos CRs
oc get elasticsearch $ES_NAME -n $APP_NS -o yaml > "$OUT/elasticsearch.yaml" || true
oc get kibana -n $APP_NS -o yaml > "$OUT/kibana.yaml" || true
oc get enterprisesearch -n $APP_NS -o yaml > "$OUT/enterprisesearch.yaml" || true

# ---- Listagens de runtime
oc get pods -n $APP_NS -o wide > "$OUT/pods.txt"
oc get sts -n $APP_NS > "$OUT/statefulsets.txt"
oc get svc -n $APP_NS -o wide > "$OUT/services.txt"
oc get route -n $APP_NS -o wide > "$OUT/routes.txt"
oc describe route -n $APP_NS > "$OUT/routes_describe.txt" || true
oc get endpoints -n $APP_NS > "$OUT/endpoints.txt"
oc get endpointslice -n $APP_NS > "$OUT/endpointslices.txt" || true
oc get pvc -n $APP_NS > "$OUT/pvcs.txt"
oc get cm -n $APP_NS > "$OUT/configmaps.txt"
oc get secret -n $APP_NS > "$OUT/secrets_list.txt"

# ---- Describe detalhado
for r in $(oc get elasticsearch $ES_NAME -n $APP_NS -o name 2>/dev/null); do oc describe -n $APP_NS "$r" > "$OUT/describe_${r//\//_}.txt"; done
for r in $(oc get kibana -n $APP_NS -o name 2>/dev/null); do oc describe -n $APP_NS "$r" > "$OUT/describe_${r//\//_}.txt"; done
for r in $(oc get enterprisesearch -n $APP_NS -o name 2>/dev/null); do oc describe -n $APP_NS "$r" > "$OUT/describe_${r//\//_}.txt"; done
for s in $(oc get svc -n $APP_NS -o name); do oc describe -n $APP_NS "$s" > "$OUT/describe_${s//\//_}.txt"; done
for p in $(oc get pods -n $APP_NS -o name); do oc describe -n $APP_NS "$p" > "$OUT/describe_${p//\//_}.txt"; done

# ---- Licença do Operator + logs
oc -n $OP_NS get configmap elastic-licensing -o yaml > "$OUT/elastic-licensing-configmap.yaml" || true
ECK_POD=$(oc get pods -n $OP_NS -o name | grep eck-operator || true)
[ -n "$ECK_POD" ] && oc logs -n $OP_NS "$ECK_POD" --all-containers > "$OUT/eck-operator.log"

# ---- Credenciais e testes de saúde via curl (se possível)
ES_PASSWORD=$(oc get secret ${ES_NAME}-es-elastic-user -n $APP_NS -o go-template='{{index .data "elastic" | base64decode}}' 2>/dev/null)
ES_SVC=${ES_NAME}-es-http.${APP_NS}.svc:9200
if [ -n "$ES_PASSWORD" ]; then
  curl -sk -u elastic:$ES_PASSWORD https://$ES_SVC/ > "$OUT/es_root.json" || true
  curl -sk -u elastic:$ES_PASSWORD https://$ES_SVC/_cluster/health?pretty > "$OUT/es_cluster_health.json" || true
  curl -sk -u elastic:$ES_PASSWORD https://$ES_SVC/_license?pretty > "$OUT/es_license.json" || true
fi

# Kibana/Enterprise Search (descobre o 1º se existir)
KB_NAME=$(oc get kibana -n $APP_NS -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$KB_NAME" ]; then
  KB_ROUTE=$(oc get route ${KB_NAME}-kb -n $APP_NS -o jsonpath='{.spec.host}' 2>/dev/null)
  [ -n "$KB_ROUTE" ] && curl -sk https://$KB_ROUTE/api/status > "$OUT/kibana_status.json"
fi

ENT_NAME=$(oc get enterprisesearch -n $APP_NS -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$ENT_NAME" ]; then
  ENT_ROUTE=$(oc get route ${ENT_NAME}-ent -n $APP_NS -o jsonpath='{.spec.host}' 2>/dev/null)
  [ -n "$ENT_ROUTE" ] && curl -sk https://$ENT_ROUTE/ent/v2/health > "$OUT/ent_health.json"
fi

# ---- Compactar
tar -czf "$OUT.tar.gz" "$OUT"
echo "Coleta gerada em: $OUT.tar.gz"
