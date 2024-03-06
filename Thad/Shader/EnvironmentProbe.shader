Shader "Thad/EnvironmentProbe"
{
    Properties
    {
        _Roughness ("Roughness", Range(0,1)) = 0.0
        [KeywordEnum(None, Box, CameraDepth)] _Projection ("Projection Mode (camera depth might be slow)", Float) = 1
        [Toggle(_ENABLE_FADE)] _ENABLE_FADE ("Enable Fade Out", Float) = 0
        _FadeStart ("Fade Out Start", Float) = 5.0
        _FadeDistance ("Fade Out Distance", Float) = 1.0
        [Enum(UnityEngine.Rendering.CullMode)] _Culling ("Culling", Float) = 2
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("ZTest", Float) = 4
        [Enum(Off,0,On,1)]_ZWrite ("ZWrite", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "ForceNoShadowCasting" = "True" }
        Cull [_Culling]
        ZTest [_ZTest]
        ZWrite [_ZWrite]

        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #pragma multi_compile _PROJECTION_NONE _PROJECTION_BOX _PROJECTION_CAMERADEPTH
            #pragma shader_feature _ENABLE_FADE

            #include "UnityCG.cginc"
            #include "UnityStandardUtils.cginc"
            #include "UnityImageBasedLighting.cginc"

            #if _PROJECTION_CAMERADEPTH
                UNITY_DECLARE_DEPTH_TEXTURE( _CameraDepthTexture );
            #endif

            struct appdata
            {
                float4 vertex : POSITION;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 pos : SV_POSITION;

                #if _PROJECTION_CAMERADEPTH
                    float4 screenPos : TEXCOORD0;
                    float3 viewPos :TEXCOORD1;
                #elif _PROJECTION_BOX
                    float3 worldPos : TEXCOORD0;
                #else //_PROJECTION_NONE
                    float3 worldViewDir : TEXCOORD0;
                #endif

                UNITY_VERTEX_OUTPUT_STEREO
            };

            half _Roughness;
            half _FadeStart;
            half _FadeDistance;

            inline float4x4 InverseViewMatrix()
            {
                float3x3 r = transpose((float3x3)UNITY_MATRIX_V);
                float3 t = -_WorldSpaceCameraPos;
                return float4x4(
                    r._m00, r._m01, r._m02, t.x,
                    r._m10, r._m11, r._m12, t.y,
                    r._m20, r._m21, r._m22, t.z,
                    0.0f, 0.0f, 0.0f, 1.0f
                    );
            }

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.pos = UnityObjectToClipPos(v.vertex);

                #if _PROJECTION_CAMERADEPTH
                    o.screenPos = ComputeScreenPos(o.pos);
                    o.viewPos = UnityObjectToViewPos(v.vertex);
                #elif _PROJECTION_BOX
                    o.worldPos = mul(unity_ObjectToWorld, v.vertex);
                #else //_PROJECTION_NONE
                    o.worldViewDir = -WorldSpaceViewDir(v.vertex);
                #endif

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                #if _PROJECTION_BOX
                    float3 worldViewDir = i.worldPos - _WorldSpaceCameraPos;
                #endif

                #if _ENABLE_FADE
                    #if _PROJECTION_CAMERADEPTH
                        half viewDistance = length(i.viewPos);
                    #elif _PROJECTION_BOX
                        half viewDistance = length(worldViewDir);
                    #else // _PROJECTION_NONE
                        half viewDistance = length(i.worldViewDir);
                    #endif

                    half fade = (viewDistance-_FadeStart) / _FadeDistance;
                    half randomValue = frac(sin(dot(i.pos.xy, float2(12.7123f, 19.345f)))*42123.45f);
                    clip(fade - randomValue);
                #endif

                #if _PROJECTION_CAMERADEPTH
                    float screenDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)));
                    float3 viewPos = i.viewPos * (screenDepth / i.viewPos.z);
                    float4x4 inverseViewMat = InverseViewMatrix();
                    float3 worldPos = -mul(inverseViewMat, float4(viewPos, 1.0f)).xyz;
                    float3 cubeMapDir = worldPos - unity_SpecCube0_ProbePosition;
                #elif _PROJECTION_BOX
                    float3 cubeMapDir = BoxProjectedCubemapDirection(
                        worldViewDir, i.worldPos, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax
                    );
                #else // _PROJECTION_NONE
                    float3 cubeMapDir = i.worldViewDir;
                #endif
                Unity_GlossyEnvironmentData envData;
                envData.roughness = _Roughness;
                envData.reflUVW = cubeMapDir;
                half3 envColor = Unity_GlossyEnvironment(
                    UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
                );
                return half4(envColor, 1.0f);
            }
            ENDCG
        }
    }
}
