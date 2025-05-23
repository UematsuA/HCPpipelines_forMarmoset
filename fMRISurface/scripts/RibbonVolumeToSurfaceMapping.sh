#!/bin/bash 

# --------------------------------------------------------------------------------
#  Usage Description Function
# --------------------------------------------------------------------------------

script_name=$(basename "${0}")

show_usage() {
	cat <<EOF

${script_name}: Sub-script of GenericfMRISurfaceProcessingPipeline.sh

EOF
}

# Allow script to return a Usage statement, before any other output or checking
if [ "$#" = "0" ]; then
    show_usage
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
source ${HCPPIPEDIR}/global/scripts/opts.shlib                 # Command line option functions

opts_ShowVersionIfRequested $@

if opts_CheckForHelpRequest $@; then
	show_usage
	exit 0
fi

# ------------------------------------------------------------------------------
#  Verify required environment variables are set and log value
# ------------------------------------------------------------------------------

log_Check_Env_Var HCPPIPEDIR
log_Check_Env_Var CARET7DIR

# ------------------------------------------------------------------------------
#  Start work
# ------------------------------------------------------------------------------

log_Msg "START"

WorkingDirectory="$1"
VolumefMRI="$2"
Session="$3"
DownsampleFolder="$4"
LowResMesh="$5"
AtlasSpaceNativeFolder="$6"
RegName="$7"
doGoodVoxels="$8"
if [[ "$#" -lt 8 ]]; then doGoodVoxels=YES;fi


if [ ${RegName} = "FS" ]; then
    RegName="reg.reg_LR"
fi

NeighborhoodSmoothing="5"
Factor="0.5"


LeftGreyRibbonValue="1"
RightGreyRibbonValue="1"

for Hemisphere in L R ; do
  if [ $Hemisphere = "L" ] ; then
    GreyRibbonValue="$LeftGreyRibbonValue"
  elif [ $Hemisphere = "R" ] ; then
    GreyRibbonValue="$RightGreyRibbonValue"
  fi    
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".white.native.surf.gii "$VolumefMRI"_SBRef.nii.gz "$WorkingDirectory"/"$Session"."$Hemisphere".white.native.nii.gz
  ${CARET7DIR}/wb_command -create-signed-distance-volume "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".pial.native.surf.gii "$VolumefMRI"_SBRef.nii.gz "$WorkingDirectory"/"$Session"."$Hemisphere".pial.native.nii.gz
  fslmaths "$WorkingDirectory"/"$Session"."$Hemisphere".white.native.nii.gz -thr 0 -bin -mul 255 "$WorkingDirectory"/"$Session"."$Hemisphere".white_thr0.native.nii.gz
  fslmaths "$WorkingDirectory"/"$Session"."$Hemisphere".white_thr0.native.nii.gz -bin "$WorkingDirectory"/"$Session"."$Hemisphere".white_thr0.native.nii.gz
  fslmaths "$WorkingDirectory"/"$Session"."$Hemisphere".pial.native.nii.gz -uthr 0 -abs -bin -mul 255 "$WorkingDirectory"/"$Session"."$Hemisphere".pial_uthr0.native.nii.gz
  fslmaths "$WorkingDirectory"/"$Session"."$Hemisphere".pial_uthr0.native.nii.gz -bin "$WorkingDirectory"/"$Session"."$Hemisphere".pial_uthr0.native.nii.gz
  fslmaths "$WorkingDirectory"/"$Session"."$Hemisphere".pial_uthr0.native.nii.gz -mas "$WorkingDirectory"/"$Session"."$Hemisphere".white_thr0.native.nii.gz -mul 255 "$WorkingDirectory"/"$Session"."$Hemisphere".ribbon.nii.gz
  fslmaths "$WorkingDirectory"/"$Session"."$Hemisphere".ribbon.nii.gz -bin -mul $GreyRibbonValue "$WorkingDirectory"/"$Session"."$Hemisphere".ribbon.nii.gz
  rm "$WorkingDirectory"/"$Session"."$Hemisphere".white.native.nii.gz "$WorkingDirectory"/"$Session"."$Hemisphere".white_thr0.native.nii.gz "$WorkingDirectory"/"$Session"."$Hemisphere".pial.native.nii.gz "$WorkingDirectory"/"$Session"."$Hemisphere".pial_uthr0.native.nii.gz
done

fslmaths "$WorkingDirectory"/"$Session".L.ribbon.nii.gz -add "$WorkingDirectory"/"$Session".R.ribbon.nii.gz "$WorkingDirectory"/ribbon_only.nii.gz
rm "$WorkingDirectory"/"$Session".L.ribbon.nii.gz "$WorkingDirectory"/"$Session".R.ribbon.nii.gz

fslmaths "$VolumefMRI" -Tmean "$WorkingDirectory"/mean -odt float
fslmaths "$VolumefMRI" -Tstd "$WorkingDirectory"/std -odt float
fslmaths "$WorkingDirectory"/std -div "$WorkingDirectory"/mean "$WorkingDirectory"/cov

fslmaths "$WorkingDirectory"/cov -mas "$WorkingDirectory"/ribbon_only.nii.gz "$WorkingDirectory"/cov_ribbon

fslmaths "$WorkingDirectory"/cov_ribbon -div $(fslstats "$WorkingDirectory"/cov_ribbon -M) "$WorkingDirectory"/cov_ribbon_norm
fslmaths "$WorkingDirectory"/cov_ribbon_norm -bin -s $NeighborhoodSmoothing "$WorkingDirectory"/SmoothNorm
fslmaths "$WorkingDirectory"/cov_ribbon_norm -s $NeighborhoodSmoothing -div "$WorkingDirectory"/SmoothNorm -dilD "$WorkingDirectory"/cov_ribbon_norm_s$NeighborhoodSmoothing
fslmaths "$WorkingDirectory"/cov -div $(fslstats "$WorkingDirectory"/cov_ribbon -M) -div "$WorkingDirectory"/cov_ribbon_norm_s$NeighborhoodSmoothing "$WorkingDirectory"/cov_norm_modulate
fslmaths "$WorkingDirectory"/cov_norm_modulate -mas "$WorkingDirectory"/ribbon_only.nii.gz "$WorkingDirectory"/cov_norm_modulate_ribbon

STD=$(fslstats "$WorkingDirectory"/cov_norm_modulate_ribbon -S)
echo $STD
MEAN=$(fslstats "$WorkingDirectory"/cov_norm_modulate_ribbon -M)
echo $MEAN
Lower=$(echo "$MEAN - ($STD * $Factor)" | bc -l)
echo $Lower
Upper=$(echo "$MEAN + ($STD * $Factor)" | bc -l)
echo $Upper

fslmaths "$WorkingDirectory"/mean -bin "$WorkingDirectory"/mask
if [[ $doGoodVoxels = YES ]];then
  fslmaths "$WorkingDirectory"/cov_norm_modulate -thr $Upper -bin -sub "$WorkingDirectory"/mask -mul -1 "$WorkingDirectory"/goodvoxels
fi

for Hemisphere in L R ; do
  for Map in mean cov ; do
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$WorkingDirectory"/"$Map".nii.gz "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$WorkingDirectory"/"$Hemisphere"."$Map".native.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".white.native.surf.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".pial.native.surf.gii -volume-roi "$WorkingDirectory"/goodvoxels.nii.gz
    ${CARET7DIR}/wb_command -metric-dilate "$WorkingDirectory"/"$Hemisphere"."$Map".native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii 10 "$WorkingDirectory"/"$Hemisphere"."$Map".native.func.gii -nearest
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map".native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map".native.func.gii
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$WorkingDirectory"/"$Map".nii.gz "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$WorkingDirectory"/"$Hemisphere"."$Map"_all.native.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".white.native.surf.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".pial.native.surf.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map"_all.native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map"_all.native.func.gii
    ${CARET7DIR}/wb_command -metric-resample "$WorkingDirectory"/"$Hemisphere"."$Map".native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".sphere.${RegName}.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$WorkingDirectory"/"$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.func.gii -area-surfs "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Session"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map"."$LowResMesh"k_fs_LR.func.gii
    ${CARET7DIR}/wb_command -metric-resample "$WorkingDirectory"/"$Hemisphere"."$Map"_all.native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".sphere.${RegName}.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$WorkingDirectory"/"$Hemisphere"."$Map"_all."$LowResMesh"k_fs_LR.func.gii -area-surfs "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere"."$Map"_all."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Session"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere"."$Map"_all."$LowResMesh"k_fs_LR.func.gii
  done
  if [[ $doGoodVoxels = YES ]];then
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$WorkingDirectory"/goodvoxels.nii.gz "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$WorkingDirectory"/"$Hemisphere".goodvoxels.native.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".white.native.surf.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".pial.native.surf.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere".goodvoxels.native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii "$WorkingDirectory"/"$Hemisphere".goodvoxels.native.func.gii
    ${CARET7DIR}/wb_command -metric-resample "$WorkingDirectory"/"$Hemisphere".goodvoxels.native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".sphere.${RegName}.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$WorkingDirectory"/"$Hemisphere".goodvoxels."$LowResMesh"k_fs_LR.func.gii -area-surfs "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii
    ${CARET7DIR}/wb_command -metric-mask "$WorkingDirectory"/"$Hemisphere".goodvoxels."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Session"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$WorkingDirectory"/"$Hemisphere".goodvoxels."$LowResMesh"k_fs_LR.func.gii
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$VolumefMRI".nii.gz "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$VolumefMRI"."$Hemisphere".native.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".white.native.surf.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".pial.native.surf.gii -volume-roi "$WorkingDirectory"/goodvoxels.nii.gz
  else
    ${CARET7DIR}/wb_command -volume-to-surface-mapping "$VolumefMRI".nii.gz "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$VolumefMRI"."$Hemisphere".native.func.gii -ribbon-constrained "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".white.native.surf.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".pial.native.surf.gii -volume-roi "$WorkingDirectory"/cov_norm_modulate.nii.gz
  fi
  ${CARET7DIR}/wb_command -metric-dilate "$VolumefMRI"."$Hemisphere".native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii 10 "$VolumefMRI"."$Hemisphere".native.func.gii -nearest
  ${CARET7DIR}/wb_command -metric-mask  "$VolumefMRI"."$Hemisphere".native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii  "$VolumefMRI"."$Hemisphere".native.func.gii
  ${CARET7DIR}/wb_command -metric-resample "$VolumefMRI"."$Hemisphere".native.func.gii "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".sphere.${RegName}.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".sphere."$LowResMesh"k_fs_LR.surf.gii ADAP_BARY_AREA "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii -area-surfs "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".midthickness.native.surf.gii "$DownsampleFolder"/"$Session"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii -current-roi "$AtlasSpaceNativeFolder"/"$Session"."$Hemisphere".roi.native.shape.gii
  ${CARET7DIR}/wb_command -metric-dilate "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Session"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii 30 "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii -nearest
  ${CARET7DIR}/wb_command -metric-mask "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii "$DownsampleFolder"/"$Session"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.shape.gii "$VolumefMRI"."$Hemisphere".atlasroi."$LowResMesh"k_fs_LR.func.gii
done

log_Msg "END"


