#ifndef _LIGHTINGSTANDARDVRCLIGHTVOLUMES_INCLUDED
#define _LIGHTINGSTANDARDVRCLIGHTVOLUMES_INCLUDED

#include "UnityCG.cginc"
#include "UnityGlobalIllumination.cginc"
#include "UnityPBSLighting.cginc"

#if !_VRCLIGHTVOLUMES_DIFFUSE_OFF || _VRCLIGHTVOLUMES_SPECULAR_ON
    #include "Packages/red.sim.lightvolumes/Shaders/LightVolumes.cginc"
#endif

inline half4 LightingStandardVRCLightVolumes(SurfaceOutputStandard s, half3 viewDir, UnityGI gi)
{
    return LightingStandard(s, viewDir, gi);
}

inline void LightingStandardVRCLightVolumes_GI(
    SurfaceOutputStandard s,
    UnityGIInput data,
    inout UnityGI gi)
{
    #if !_VRCLIGHTVOLUMES_DIFFUSE_OFF || _VRCLIGHTVOLUMES_SPECULAR_ON
        float3 L0;
        float3 L1r;
        float3 L1g;
        float3 L1b;
        #if defined(LIGHTMAP_ON) && !_VRCLIGHTVOLUMES_DIFFUSE_OFF
            LightVolumeAdditiveSH(data.worldPos, L0, L1r, L1g, L1b);
        #else
            LightVolumeSH(data.worldPos, L0, L1r, L1g, L1b);
        #endif
    #endif

    #if defined(LIGHTMAP_ON) || _VRCLIGHTVOLUMES_DIFFUSE_OFF
        gi = UnityGI_Base(data, s.Occlusion, s.Normal);
    #else
        ResetUnityGI(gi);
    #endif

    #if !_VRCLIGHTVOLUMES_DIFFUSE_OFF
        gi.indirect.diffuse += LightVolumeEvaluate(s.Normal, L0, L1r, L1g, L1b) * s.Occlusion;
    #endif

    Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.Smoothness, data.worldViewDir, s.Normal, lerp(unity_ColorSpaceDielectricSpec.rgb, s.Albedo, s.Metallic));
    gi.indirect.specular = UnityGI_IndirectSpecular(data, s.Occlusion, g);

    #if _VRCLIGHTVOLUMES_SPECULAR_ON
        gi.indirect.specular += LightVolumeSpecular(s.Albedo, s.Smoothness, s.Metallic, s.Normal, data.worldViewDir, L0, L1r, L1g, L1b) * s.Occlusion;
    #endif
}

#endif //_LIGHTINGSTANDARDVRCLIGHTVOLUMES_INCLUDED
