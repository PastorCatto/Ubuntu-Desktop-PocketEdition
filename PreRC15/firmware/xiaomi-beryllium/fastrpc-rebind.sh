#!/bin/sh
# Mobuntu Orange — fastrpc-rebind.sh
# qcom_q6v5_adsp and qcom_q6v5_pas are blacklisted at boot.
# This service loads them after rmtfs and pd-mapper are confirmed active,
# so the ADSP has a live rmtfs to call back into when it probes.
# ath10k_snoc is loaded last since it depends on the ADSP glink channel.

log() { echo "fastrpc-rebind: $1"; logger -t fastrpc-rebind "$1"; }

log "loading ADSP remoteproc after rmtfs + pd-mapper..."
modprobe qcom_q6v5_common && log "qcom_q6v5_common OK" || log "WARNING: qcom_q6v5_common failed"
modprobe qcom_q6v5_pas    && log "qcom_q6v5_pas OK"    || log "WARNING: qcom_q6v5_pas failed"
modprobe qcom_q6v5_adsp   && log "qcom_q6v5_adsp OK"   || log "WARNING: qcom_q6v5_adsp failed"
modprobe qcom_fastrpc     && log "qcom_fastrpc OK"      || log "WARNING: qcom_fastrpc failed"

log "waiting 2s for ADSP to settle before loading ath10k..."
sleep 2

modprobe ath10k_core  && log "ath10k_core OK"  || log "WARNING: ath10k_core failed"
modprobe ath10k_snoc  && log "ath10k_snoc OK"  || log "WARNING: ath10k_snoc failed"

log "done."

