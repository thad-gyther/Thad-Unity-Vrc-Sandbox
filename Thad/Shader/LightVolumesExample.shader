Shader "Thad/LightVolumesExample"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _Occlusion ("Occlusion", Range(0,1)) = 1.0
        [ToggleOff] _SpecularHighlights("Specular Highlights (Regular Lights)", Float) = 1.0
        [ToggleOff] _GlossyReflections("Reflections", Float) = 1.0
        [ToggleOff] _VRCLightVolumes_Diffuse ("VRC Light Volumes Diffuse", Float) = 1.0
        [Toggle] _VRCLIGHTVOLUMES_SPECULAR ("VRC Light Volumes Specular", Float) = 0.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200

        CGPROGRAM
        #pragma surface surf StandardVRCLightVolumes novertexlights
        #pragma target 5.0

        #pragma shader_feature_local _VRCLIGHTVOLUMES_DIFFUSE_OFF
        #pragma shader_feature_local _VRCLIGHTVOLUMES_SPECULAR_ON
        #pragma shader_feature_local _GLOSSYREFLECTIONS_OFF
        #pragma shader_feature_local _SPECULARHIGHLIGHTS_OFF

        #include "LightingStandardVRCLightVolumes.cginc"

        sampler2D _MainTex;

        struct Input
        {
            float2 uv_MainTex;
        };

        half _Glossiness;
        half _Metallic;
        half _Occlusion;
        fixed4 _Color;

        // Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
        // See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
        // #pragma instancing_options assumeuniformscaling
        UNITY_INSTANCING_BUFFER_START(Props)
            // put more per-instance properties here
        UNITY_INSTANCING_BUFFER_END(Props)

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            // Albedo comes from a texture tinted by color
            fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            // Metallic and smoothness come from slider variables
            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Occlusion = _Occlusion;
            o.Alpha = c.a;
        }
        ENDCG
    }
    FallBack "Standard"
}
