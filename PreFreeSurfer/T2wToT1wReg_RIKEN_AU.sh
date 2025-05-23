#!/bin/bash
set -e

# Requirements for this script
#  installed versions of: FSL
#  environment: HCPPIPEDIR, FSLDIR

# ------------------------------------------------------------------------------
#  Usage Description Function
# ------------------------------------------------------------------------------

script_name=$(basename "${0}")

Usage() {
	cat <<EOF

${script_name}: Script for registering T2w to T1w

Usage: ${script_name}

Usage information To Be Written

EOF
}

# Allow script to return a Usage statement, before any other output or checking
if [ "$#" = "0" ]; then
    Usage
    exit 1
fi

# ------------------------------------------------------------------------------
#  Check that HCPPIPEDIR is defined and Load Function Libraries
# ------------------------------------------------------------------------------

if [ -z "${HCPPIPEDIR}" ]; then
  echo "${script_name}: ABORTING: HCPPIPEDIR environment variable must be set"
  exit 1
fi

source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib


################################################ SUPPORT FUNCTIONS ##################################################

# NONE

########################################## DO WORK ##########################################

log_Msg "START: T2w2T1Reg"

WD="$1"
T1wImage="$2"
T1wImageBrain="$3"
T2wImage="$4"
T2wImageBrain="$5"
OutputT1wImage="$6"
OutputT1wImageBrain="$7"
OutputT1wTransform="$8"
OutputT2wImage="$9"
OutputT2wTransform="${10}"
Identmat="${11}"

T1wImageBrainFile=`basename "$T1wImageBrain"`

echo "$T2wImage"

${FSLDIR}/bin/imcp "$T1wImageBrain" "$WD"/"$T1wImageBrainFile"

if [ "${T2wImage}" = "NONE" ] ; then
    log_Msg "Skipping T2w to T1w registration --- no T2w image."

  elif  [ "$Identmat" != "TRUE" ] ; then
    #${FSLDIR}/bin/epi_reg --epi="$T2wImageBrain" --t1="$T1wImage" --t1brain="$WD"/"$T1wImageBrainFile" --out="$WD"/T2w2T1w
      $HCPPIPEDIR/global/scripts/epi_reg_dof --epi="$T2wImageBrain" --t1="$WD"/"$T1wImageBrainFile" --t1brain="$WD"/"$T1wImageBrainFile" --out="$WD"/T2w2T1w
  else
      ${FSLDIR}/bin/imcp "$T2wImageBrain" "$WD"/T2w2T1w
        echo "1 0 0 0" > "$WD"/T2w2T1w.mat
        echo "0 1 0 0" >> "$WD"/T2w2T1w.mat
        echo "0 0 1 0" >> "$WD"/T2w2T1w.mat
        echo "0 0 0 1" >> "$WD"/T2w2T1w.mat
    ${FSLDIR}/bin/applywarp --rel --interp=spline --in="$T2wImage" --ref="$T1wImage" --premat="$WD"/T2w2T1w.mat --out="$WD"/T2w2T1w
    ${FSLDIR}/bin/fslmaths "$WD"/T2w2T1w -add 1 "$WD"/T2w2T1w -odt float
fi

  ${FSLDIR}/bin/imcp "$T1wImage".nii.gz "$OutputT1wImage".nii.gz
  ${FSLDIR}/bin/imcp "$T1wImageBrain".nii.gz "$OutputT1wImageBrain".nii.gz
  ${FSLDIR}/bin/fslmerge -t $OutputT1wTransform "$T1wImage".nii.gz "$T1wImage".nii.gz "$T1wImage".nii.gz
  ${FSLDIR}/bin/fslmaths $OutputT1wTransform -mul 0 $OutputT1wTransform

if [ ! "${T2wImage}" = "NONE" ] ; then
		${FSLDIR}/bin/applywarp --rel --interp=spline --in="$T2wImage" --ref="$T1wImage" --premat="$WD"/T2w2T1w.mat --out="$WD"/T2w2T1w
		${FSLDIR}/bin/imcp "$WD"/T2w2T1w.nii.gz "$OutputT2wImage".nii.gz
    ${FSLDIR}/bin/convertwarp --relout --rel -r "$OutputT2wImage".nii.gz -w $OutputT1wTransform --postmat="$WD"/T2w2T1w.mat --out="$OutputT2wTransform"
fi

log_Msg "END: T2w2T1Reg"
