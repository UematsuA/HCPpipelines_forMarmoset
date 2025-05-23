#!/bin/bash 

# Requirements for this script
#  installed versions of: FSL, gradunwarp (HCP version)
#  environment: HCPPIPEDIR, FSLDIR, HCPPIPEDIR_Global, PATH for gradient_unwarp.py

################################################ SUPPORT FUNCTIONS ##################################################

# --------------------------------------------------------------------------------
#  Load Function Libraries
# --------------------------------------------------------------------------------

set -eu

pipedirguessed=0
if [[ "${HCPPIPEDIR:-}" == "" ]]
then
    pipedirguessed=1
    #fix this if the script is more than one level below HCPPIPEDIR
    export HCPPIPEDIR="$(dirname -- "$0")/../.."
fi

# Load function libraries
source "${HCPPIPEDIR}/global/scripts/debug.shlib" "$@"         # Debugging functions; also sources log.shlib
source "$HCPPIPEDIR/global/scripts/newopts.shlib" "$@"

opts_SetScriptDescription "Script for using topup to do distortion correction for EPI (scout)"

opts_AddMandatory '--phaseone' 'PhaseEncodeOne' 'image(s)' "first set of SE EPI images: assumed to be the 'negative' PE direction"

opts_AddMandatory '--phasetwo' 'PhaseEncodeTwo' 'image(s)' "second set of SE EPI images: assumed to be the 'positive' PE direction"

opts_AddMandatory '--scoutin' 'ScoutInputName' 'image' "scout input image: should be corrected for gradient non-linear distortions"

opts_AddMandatory '--echospacing' 'EchoSpacing' 'number (seconds)' "effective echo spacing of EPI or in seconds"

opts_AddMandatory '--unwarpdir' 'UnwarpDir' '{x,y,x-,y-} or {i,j,i-,j-}' "PE direction for unwarping according to the *voxel* axes"

opts_AddMandatory '--gdcoeffs' 'GradientDistortionCoeffs' 'file' "gradient non-linearity distortion coefficients (Siemens format)"

#Optional Args 
opts_AddOptional '--workingdir' 'WD' 'path' 'working dir'

opts_AddOptional '--owarp' 'DistortionCorrectionWarpFieldOutput' 'image' "output warpfield image: scout to distortion corrected SE EPI"

opts_AddOptional '--ofmapmag' 'DistortionCorrectionMagnitudeOutput' 'image' "output 'Magnitude' image: scout to distortion corrected SE EPI"

opts_AddOptional '--ofmapmagbrain' 'DistortionCorrectionMagnitudeBrainOutput' 'image' "output 'Magnitude' brain image: scout to distortion corrected SE EPI"

opts_AddOptional '--ofmap' 'DistortionCorrectionFieldOutput' 'image' "output scaled topup field map image"

opts_AddOptional '--ojacobian' 'JacobianOutput' 'image' "output Jacobian image (of the TOPUP warp field)"

opts_AddOptional '--topupconfig' 'TopupConfig' 'path' "topup config file"

opts_AddOptional '--usejacobian' 'UseJacobian' 'true or false' "Whether to apply the jacobian of the gradient non-linearity distortion correction.  Irrelevant if --gdcoeffs=NONE (Has nothing to do with the jacobian of the TOPUP warp field)"
# added for marmoset data by A.Uematsu on 2024/09/03
opts_AddOptional '--species' 'SPECIES' 'Human, Macaque, or Marmoset' "Processing either Human or Nonhuman primates paramteters.  'Humans' (the default) follows the HCP processing steps" # added by A.Uematsu on 2024/2/3

opts_ParseArguments "$@"

if ((pipedirguessed))
then
    log_Err_Abort "HCPPIPEDIR is not set, you must first source your edited copy of Examples/Scripts/SetUpHCPPipeline.sh"
fi

#display the parsed/default values
opts_ShowValues

# Verify required environment variables are set and log value
log_Check_Env_Var FSLDIR

################################################### OUTPUT FILES #####################################################

# Output images (in $WD): 
#          BothPhases      (input to topup - combines both pe direction data, plus masking)
#          SBRef2PhaseOne_gdc.mat SBRef2PhaseOne_gdc   (linear registration result)
#          PhaseOne_gdc  PhaseTwo_gdc
#          PhaseOne_gdc_dc  PhaseOne_gdc_dc_jac  PhaseTwo_gdc_dc  PhaseTwo_gdc_dc_jac
#          SBRef_dc   SBRef_dc_jac
#          WarpField  Jacobian
# Output images (not in $WD): 
#          ${DistortionCorrectionWarpFieldOutput}  ${JacobianOutput}

#sanity check the jacobian option
UseJacobian=$(opts_StringToBool "$UseJacobian")

GlobalScripts=${HCPPIPEDIR_Global}

# deal with default that depends on another argument
DistortionCorrectionWarpFieldOutput=$("$FSLDIR"/bin/remove_ext "$DistortionCorrectionWarpFieldOutput")
if [[ $WD == "" ]]
then
    WD=${DistortionCorrectionWarpFieldOutput}.wdir
fi

log_Msg "START: Topup Field Map Generation and Gradient Unwarping"

mkdir -p "$WD"

# Record the input options in a log file
echo "$0 $@" >> $WD/log.txt
echo "PWD = `pwd`" >> $WD/log.txt
echo "date: `date`" >> $WD/log.txt
echo " " >> $WD/log.txt

########################################## DO WORK ########################################## 

#check dimensions of phase versus sbref images
#should we also check spacing info? could be off by tiny fractions, so probably not
if [[ `fslhd $PhaseEncodeOne | grep '^dim[123]'` != `fslhd $ScoutInputName | grep '^dim[123]'` ]]
then
    log_Err_Abort "Spin echo fieldmap has different dimensions than scout image, this requires a manual fix"
fi
#for kicks, check that the spin echo images match
if [[ `fslhd $PhaseEncodeOne | grep '^dim[123]'` != `fslhd $PhaseEncodeTwo | grep '^dim[123]'` ]]
then
    log_Err_Abort "Spin echo fieldmap images have different dimensions!"
fi

# PhaseOne and PhaseTwo are sets of SE EPI images with opposite phase encodes
${FSLDIR}/bin/imcp $PhaseEncodeOne ${WD}/PhaseOne
${FSLDIR}/bin/imcp $PhaseEncodeTwo ${WD}/PhaseTwo
${FSLDIR}/bin/imcp $ScoutInputName ${WD}/SBRef

# Apply gradient non-linearity distortion correction to input images (SE pair)
if [ ! $GradientDistortionCoeffs = "NONE" ] ; then
  ${GlobalScripts}/GradientDistortionUnwarp.sh \
      --workingdir=${WD} \
      --coeffs=${GradientDistortionCoeffs} \
      --in=${WD}/PhaseOne \
      --out=${WD}/PhaseOne_gdc \
      --owarp=${WD}/PhaseOne_gdc_warp
  ${GlobalScripts}/GradientDistortionUnwarp.sh \
      --workingdir=${WD} \
      --coeffs=${GradientDistortionCoeffs} \
      --in=${WD}/PhaseTwo \
      --out=${WD}/PhaseTwo_gdc \
      --owarp=${WD}/PhaseTwo_gdc_warp

  if ((UseJacobian))
  then
    ${FSLDIR}/bin/fslmaths ${WD}/PhaseOne_gdc -mul ${WD}/PhaseOne_gdc_warp_jacobian ${WD}/PhaseOne_gdc
    ${FSLDIR}/bin/fslmaths ${WD}/PhaseTwo_gdc -mul ${WD}/PhaseTwo_gdc_warp_jacobian ${WD}/PhaseTwo_gdc
  fi
  #overwrites inputs, no else needed
  
  #in the below stuff, the jacobians for both phases and sbref are applied unconditionally to a separate _jac image
  #NOTE: "SBref" is actually the input scout, which is actually the _gdc scout, with gdc jacobian applied if applicable

  # Make a dilated mask in the distortion corrected space
  # 6/5/2019: Ensure that the mask is a single volume (via -Tmin flag) to handle changes in behavior of flirt and
  # applywarp introduced with FSL 6 (e.g., with a 3 frame input as the ref (-r) volume, applywarp results in a 9 frame output)
  ${FSLDIR}/bin/fslmaths ${WD}/PhaseOne -abs -bin -dilD -Tmin ${WD}/PhaseOne_mask
  ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${WD}/PhaseOne_mask -r ${WD}/PhaseOne_mask -w ${WD}/PhaseOne_gdc_warp -o ${WD}/PhaseOne_mask_gdc
  ${FSLDIR}/bin/fslmaths ${WD}/PhaseTwo -abs -bin -dilD -Tmin ${WD}/PhaseTwo_mask
  ${FSLDIR}/bin/applywarp --rel --interp=nn -i ${WD}/PhaseTwo_mask -r ${WD}/PhaseTwo_mask -w ${WD}/PhaseTwo_gdc_warp -o ${WD}/PhaseTwo_mask_gdc

  # Make a conservative (eroded) intersection of the two masks
  ${FSLDIR}/bin/fslmaths ${WD}/PhaseOne_mask_gdc -mas ${WD}/PhaseTwo_mask_gdc -ero -bin ${WD}/Mask
  # Merge both sets of images
  ${FSLDIR}/bin/fslmerge -t ${WD}/BothPhases ${WD}/PhaseOne_gdc ${WD}/PhaseTwo_gdc

else 
  ${FSLDIR}/bin/imcp ${WD}/PhaseOne ${WD}/PhaseOne_gdc
  ${FSLDIR}/bin/imcp ${WD}/PhaseTwo ${WD}/PhaseTwo_gdc
  fslmerge -t ${WD}/BothPhases ${WD}/PhaseOne_gdc ${WD}/PhaseTwo_gdc
  fslmaths ${WD}/BothPhases -mul 0 -add 1 -Tmin ${WD}/Mask  # Single volume containing all 1's
fi


# Set up text files with all necessary parameters
txtfname=${WD}/acqparams.txt
if [ -e $txtfname ] ; then
  rm $txtfname
fi

dimtOne=`${FSLDIR}/bin/fslval ${WD}/PhaseOne dim4`
dimtTwo=`${FSLDIR}/bin/fslval ${WD}/PhaseTwo dim4`

# Calculate the readout time and populate the parameter file appropriately
# Total_readout=EffectiveEchoSpacing*(ReconMatrixPE-1)
#  Factors such as in-plane acceleration, phase oversampling, phase resolution, phase field-of-view, and interpolation
#  must already be accounted for as part of the "EffectiveEchoSpacing"

# For UnwarpDir, allow for both {x,y} and {i,j} nomenclature
# X direction phase encode
if [[ $UnwarpDir = [xi] || $UnwarpDir = [xi]- || $UnwarpDir = -[xi] ]] ; then
  dimP=`${FSLDIR}/bin/fslval ${WD}/PhaseOne dim1`
  dimPminus1=$(($dimP - 1))
  ro_time=`echo "scale=6; ${EchoSpacing} * ${dimPminus1}" | bc -l` #Compute Total_readout in secs with up to 6 decimal places
  log_Msg "Total readout time is $ro_time secs"
  i=1
  while [ $i -le $dimtOne ] ; do
    echo "-1 0 0 $ro_time" >> $txtfname
    ShiftOne="x-"
    i=`echo "$i + 1" | bc`
  done
  i=1
  while [ $i -le $dimtTwo ] ; do
    echo "1 0 0 $ro_time" >> $txtfname
    ShiftTwo="x"
    i=`echo "$i + 1" | bc`
  done
# Y direction phase encode
elif [[ $UnwarpDir = [yj] || $UnwarpDir = [yj]- || $UnwarpDir = -[yj] ]] ; then
  dimP=`${FSLDIR}/bin/fslval ${WD}/PhaseOne dim2`
  dimPminus1=$(($dimP - 1))
  ro_time=`echo "scale=6; ${EchoSpacing} * ${dimPminus1}" | bc -l` #Compute Total_readout in secs with up to 6 decimal places
  i=1
  while [ $i -le $dimtOne ] ; do
    echo "0 -1 0 $ro_time" >> $txtfname
    ShiftOne="y-"
    i=`echo "$i + 1" | bc`
  done
  i=1
  while [ $i -le $dimtTwo ] ; do
    echo "0 1 0 $ro_time" >> $txtfname
    ShiftTwo="y"
    i=`echo "$i + 1" | bc`
  done
else
	# Per Jesper Anderson, topup does NOT allow PE dir to be along Z (no good reason, other than that made implementation easier)
	log_Err_Abort "Invalid entry for --unwarpdir ($UnwarpDir)"
fi

#Pad in Z by one slice if odd so that topup does not complain (slice consists of zeros that will be dilated by following step)
numslice=`fslval ${WD}/BothPhases dim3`
if [ ! $(($numslice % 2)) -eq "0" ] ; then
  log_Msg "Padding Z by one slice"
  for Image in ${WD}/BothPhases ${WD}/Mask ; do
    fslroi ${Image} ${WD}/slice 0 -1 0 -1 0 1 0 -1
    fslmaths ${WD}/slice -mul 0 ${WD}/slice
    fslmerge -z ${Image} ${Image} ${WD}/slice
    ${FSLDIR}/bin/imrm ${WD}/slice
  done
fi

# Extrapolate the existing values beyond the mask (adding 1 just to avoid smoothing inside the mask)
${FSLDIR}/bin/fslmaths ${WD}/BothPhases -abs -add 1 -mas ${WD}/Mask -dilM -dilM -dilM -dilM -dilM ${WD}/BothPhases

# RUN TOPUP
# Needs FSL (version 5.0.6 or later)
# Note: All the jacobian stuff from here onward is related to the TOPUP warp field
${FSLDIR}/bin/topup --imain=${WD}/BothPhases --datain=$txtfname --config=${TopupConfig} --out=${WD}/Coefficents --iout=${WD}/Magnitudes --fout=${WD}/TopupField --dfout=${WD}/WarpField --rbmout=${WD}/MotionMatrix --jacout=${WD}/Jacobian -v 

#Remove Z slice padding if needed
if [ ! $(($numslice % 2)) -eq "0" ] ; then
  log_Msg "Removing Z slice padding"
  for Image in ${WD}/BothPhases ${WD}/Mask ${WD}/Coefficents_fieldcoef ${WD}/Magnitudes ${WD}/TopupField* ${WD}/WarpField* ${WD}/Jacobian* ; do
    fslroi ${Image} ${Image} 0 -1 0 -1 0 ${numslice} 0 -1
  done
fi

# UNWARP DIR = x,y
if [[ $UnwarpDir = [xyij] ]] ; then
  # select the first volume from PhaseTwo
  VolumeNumber=$(($dimtOne + 1))
  vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
  # register scout to SE input (PhaseTwo) + combine motion and distortion correction
  ${FSLDIR}/bin/fslroi ${WD}/PhaseTwo_gdc ${WD}/PhaseTwo_gdc_one 0 1  # For flirt in FSL 6, -ref argument must be single 3D volume
  ${FSLDIR}/bin/flirt -dof 6 -interp spline -in ${WD}/SBRef -ref ${WD}/PhaseTwo_gdc_one -omat ${WD}/SBRef2PhaseTwo_gdc.mat -out ${WD}/SBRef2PhaseTwo_gdc
  ${FSLDIR}/bin/convert_xfm -omat ${WD}/SBRef2WarpField.mat -concat ${WD}/MotionMatrix_${vnum}.mat ${WD}/SBRef2PhaseTwo_gdc.mat
  ${FSLDIR}/bin/convertwarp --relout --rel -r ${WD}/PhaseTwo_gdc_one --premat=${WD}/SBRef2WarpField.mat --warp1=${WD}/WarpField_${vnum} --out=${WD}/WarpField
  ${FSLDIR}/bin/imcp ${WD}/Jacobian_${vnum} ${WD}/Jacobian
  SBRefPhase=Two
# UNWARP DIR = -x,-y
elif [[ $UnwarpDir = [xyij]- || $UnwarpDir = -[xyij] ]] ; then
  # select the first volume from PhaseOne
  VolumeNumber=$((0 + 1))
  vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
  # register scout to SE input (PhaseOne) + combine motion and distortion correction
  ${FSLDIR}/bin/fslroi ${WD}/PhaseOne_gdc ${WD}/PhaseOne_gdc_one 0 1  # For flirt in FSL 6, -ref argument must be single 3D volume
  ${FSLDIR}/bin/flirt -dof 6 -interp spline -in ${WD}/SBRef -ref ${WD}/PhaseOne_gdc_one -omat ${WD}/SBRef2PhaseOne_gdc.mat -out ${WD}/SBRef2PhaseOne_gdc
  ${FSLDIR}/bin/convert_xfm -omat ${WD}/SBRef2WarpField.mat -concat ${WD}/MotionMatrix_${vnum}.mat ${WD}/SBRef2PhaseOne_gdc.mat
  ${FSLDIR}/bin/convertwarp --relout --rel -r ${WD}/PhaseOne_gdc_one --premat=${WD}/SBRef2WarpField.mat --warp1=${WD}/WarpField_${vnum} --out=${WD}/WarpField
  ${FSLDIR}/bin/imcp ${WD}/Jacobian_${vnum} ${WD}/Jacobian
  SBRefPhase=One
fi

# Make sure that the -r volume in applywarp is a single 3D volume to deal with changes (bug) in behavior
# of applywarp introduced with FSL 6

# PhaseTwo (first vol) - warp and Jacobian modulate to get distortion corrected output
VolumeNumber=$(($dimtOne + 1))
  vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/PhaseTwo_gdc -r ${WD}/Mask --premat=${WD}/MotionMatrix_${vnum}.mat -w ${WD}/WarpField_${vnum} -o ${WD}/PhaseTwo_gdc_dc
${FSLDIR}/bin/fslmaths ${WD}/PhaseTwo_gdc_dc -mul ${WD}/Jacobian_${vnum} ${WD}/PhaseTwo_gdc_dc_jac
# PhaseOne (first vol) - warp and Jacobian modulate to get distortion corrected output
VolumeNumber=$((0 + 1))
  vnum=`${FSLDIR}/bin/zeropad $VolumeNumber 2`
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/PhaseOne_gdc -r ${WD}/Mask --premat=${WD}/MotionMatrix_${vnum}.mat -w ${WD}/WarpField_${vnum} -o ${WD}/PhaseOne_gdc_dc
${FSLDIR}/bin/fslmaths ${WD}/PhaseOne_gdc_dc -mul ${WD}/Jacobian_${vnum} ${WD}/PhaseOne_gdc_dc_jac

# Scout - warp and Jacobian modulate to get distortion corrected output
${FSLDIR}/bin/applywarp --rel --interp=spline -i ${WD}/SBRef -r ${WD}/SBRef -w ${WD}/WarpField -o ${WD}/SBRef_dc
${FSLDIR}/bin/fslmaths ${WD}/SBRef_dc -mul ${WD}/Jacobian ${WD}/SBRef_dc_jac

# Calculate Equivalent Field Map
${FSLDIR}/bin/fslmaths ${WD}/TopupField -mul 6.283 ${WD}/TopupField
${FSLDIR}/bin/fslmaths ${WD}/Magnitudes -Tmean ${WD}/Magnitude
if [ "$SPECIES" = "Marmoset" ] ; then 
	 antsRegistrationSyN.sh -d 3 -m $(dirname ${WD})/T2w_acpc_dc_restore.nii.gz -f ${WD}/Magnitude.nii.gz -t r -o ${WD}/Mask_
	 antsApplyTransforms -d 3 -i $(dirname ${WD})/T2w_acpc_dc_restore_brain.nii.gz -o ${WD}/Magnitude_brain.nii.gz -r ${WD}/Magnitude.nii.gz -n NearestNeighbor -v -t ${WD}/Mask_0GenericAffine.mat
	 fslmaths ${WD}/Magnitude_brain.nii.gz  -bin -dilD ${WD}/Magnitude_brain_mask.nii.gz
	 fslmaths ${WD}/Magnitude.nii.gz -mas ${WD}/Magnitude_brain_mask.nii.gz ${WD}/Magnitude_brain.nii.gz
else
	${FSLDIR}/bin/bet ${WD}/Magnitude ${WD}/Magnitude_brain -f 0.35 -m #Brain extract the magnitude image
fi
# copy images to specified outputs
# explicitly include .nii.gz suffix on outputs here, to avoid any ambiguity between files
# vs directories with the same (base)name
if [ ! -z ${DistortionCorrectionWarpFieldOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/WarpField.nii.gz ${DistortionCorrectionWarpFieldOutput}.nii.gz
fi
if [ ! -z ${JacobianOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/Jacobian.nii.gz ${JacobianOutput}.nii.gz
fi
if [ ! -z ${DistortionCorrectionFieldOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/TopupField.nii.gz ${DistortionCorrectionFieldOutput}.nii.gz
fi
if [ ! -z ${DistortionCorrectionMagnitudeOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/Magnitude.nii.gz ${DistortionCorrectionMagnitudeOutput}.nii.gz
fi
if [ ! -z ${DistortionCorrectionMagnitudeBrainOutput} ] ; then
  ${FSLDIR}/bin/imcp ${WD}/Magnitude_brain.nii.gz ${DistortionCorrectionMagnitudeBrainOutput}.nii.gz
fi

log_Msg "END: Topup Field Map Generation and Gradient Unwarping"
echo " END: `date`" >> $WD/log.txt

########################################## QA STUFF ########################################## 

if [ -e $WD/qa.txt ] ; then rm -f $WD/qa.txt ; fi
echo "cd `pwd`" >> $WD/qa.txt
echo "# Inspect results of various corrections (phase one)" >> $WD/qa.txt
echo "fslview ${WD}/PhaseOne ${WD}/PhaseOne_gdc ${WD}/PhaseOne_gdc_dc ${WD}/PhaseOne_gdc_dc_jac" >> $WD/qa.txt
echo "# Inspect results of various corrections (phase two)" >> $WD/qa.txt
echo "fslview ${WD}/PhaseTwo ${WD}/PhaseTwo_gdc ${WD}/PhaseTwo_gdc_dc ${WD}/PhaseTwo_gdc_dc_jac" >> $WD/qa.txt
echo "# Check linear registration of Scout to SE EPI" >> $WD/qa.txt
echo "fslview ${WD}/Phase${SBRefPhase}_gdc ${WD}/SBRef2Phase${SBRefPhase}_gdc" >> $WD/qa.txt
echo "# Inspect results of various corrections to scout" >> $WD/qa.txt
echo "fslview ${WD}/SBRef ${WD}/SBRef_dc ${WD}/SBRef_dc_jac" >> $WD/qa.txt
echo "# Visual check of warpfield and Jacobian" >> $WD/qa.txt
echo "fslview ${DistortionCorrectionWarpFieldOutput} ${JacobianOutput}" >> $WD/qa.txt


##############################################################################################



