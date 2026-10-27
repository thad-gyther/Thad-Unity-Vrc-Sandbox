Shader "Thad/EnvironmentProbe"
{
    Properties
    {
        _Roughness ("Roughness", Range(0,1)) = 0.0
        [KeywordEnum(None, Box, ForceBox, CustomBox, CameraDepth)] _Projection ("Projection Mode (camera depth might be slow)", Float) = 1
        _CustomProbeBoundsMin ("Custom Probe Bounds Min", Vector) = (-10,0,-10,0)
        _CustomProbeBoundsMax ("Custom Probe Bounds Max", Vector) = (10,10,10,0)

        [Toggle(_ENABLE_FADE)] _ENABLE_FADE ("Enable Fade Out", Float) = 0
        _FadeStart ("Fade Out Start", Float) = 5.0
        _FadeDistance ("Fade Out Distance", Float) = 1.0
        [Enum(UnityEngine.Rendering.CullMode)] _Culling ("Culling", Float) = 2
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("ZTest", Float) = 4
        [Enum(Off,0,On,1)]_ZWrite ("ZWrite", Float) = 1
    }
    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque"
            "IgnoreProjector" = "True"
            "ForceNoShadowCasting" = "True" // remove if shadow casting is wanted and include commented out shadow caster at bottom
        }
        Cull [_Culling]
        ZTest [_ZTest]
        ZWrite [_ZWrite]

        LOD 100

        Pass
        {
            Tags {"LightMode"="ForwardBase"}
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #pragma shader_feature_local _PROJECTION_NONE _PROJECTION_BOX _PROJECTION_FORCEBOX _PROJECTION_CUSTOMBOX _PROJECTION_CAMERADEPTH
            #pragma shader_feature_local _ENABLE_FADE

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

                #if _PROJECTION_BOX || _PROJECTION_FORCEBOX || _PROJECTION_CUSTOMBOX || _PROJECTION_CAMERADEPTH
                    float3 worldPos : TEXCOORD0;
                    #if _PROJECTION_CAMERADEPTH
                        float4 screenPos : TEXCOORD1;
                    #endif
                #else //_PROJECTION_NONE
                    float3 worldViewDir : TEXCOORD0;
                #endif

                UNITY_VERTEX_OUTPUT_STEREO
            };

            half _Roughness;
            half _FadeStart;
            half _FadeDistance;

            float3 _CustomProbeBoundsMin;
            float3 _CustomProbeBoundsMax;

            inline float rnd(float2 p)
            {
                #if 0
                    return frac(sin(dot(p, float2(12.7123, 19.345)))*42123.45);
                #else
                    p = frac(p * 0.1031);
                    p += dot(p, p.yx + 33.33);
                    return frac(p.x * p.y);
                #endif
            }

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex);
                o.pos = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));

                #if _PROJECTION_BOX || _PROJECTION_FORCEBOX || _PROJECTION_CUSTOMBOX || _PROJECTION_CAMERADEPTH
                    o.worldPos = worldPos;
                    #if _PROJECTION_CAMERADEPTH
                        o.screenPos = ComputeScreenPos(o.pos);
                    #endif
                #else //_PROJECTION_NONE
                    o.worldViewDir = worldPos - _WorldSpaceCameraPos;
                #endif

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                #if _PROJECTION_BOX || _PROJECTION_FORCEBOX || _PROJECTION_CUSTOMBOX || _PROJECTION_CAMERADEPTH
                    float3 worldViewDir = i.worldPos.xyz - _WorldSpaceCameraPos.xyz;
                #else
                    float3 worldViewDir = i.worldViewDir.xyz;
                #endif

                #if _ENABLE_FADE
                    half viewDistance = length(worldViewDir);
                    half fade = (viewDistance - _FadeStart) / _FadeDistance;
                    half randomValue = rnd(i.pos.xy);
                    clip(fade - randomValue);
                #endif

                #if _PROJECTION_CAMERADEPTH
                    float screenDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)));
                    float fragmentDepth = LinearEyeDepth(i.screenPos.z / i.screenPos.w);
                    float depthRatio = screenDepth / fragmentDepth;
                    float3 worldPos = _WorldSpaceCameraPos.xyz + (worldViewDir * depthRatio);
                    float3 cubeMapDir = worldPos - unity_SpecCube0_ProbePosition;
                #elif _PROJECTION_BOX || _PROJECTION_FORCEBOX || _PROJECTION_CUSTOMBOX
                    float4 boxMin = unity_SpecCube0_BoxMin;
                    float4 boxMax = unity_SpecCube0_BoxMax;
                    float4 probePosition = unity_SpecCube0_ProbePosition;
                    #if _PROJECTION_FORCEBOX || _PROJECTION_CUSTOMBOX
                        probePosition.w = 1.0;
                    #endif
                    #if _PROJECTION_CUSTOMBOX
                        boxMin.xyz = _CustomProbeBoundsMin.xyz;
                        boxMax.xyz = _CustomProbeBoundsMax.xyz;
                    #endif
                    float3 cubeMapDir = BoxProjectedCubemapDirection(
                        worldViewDir, i.worldPos, probePosition, boxMin, boxMax
                    );
                #else // _PROJECTION_NONE
                    float3 cubeMapDir = worldViewDir;
                #endif
                Unity_GlossyEnvironmentData envData;
                envData.roughness = _Roughness;
                envData.reflUVW = cubeMapDir;
                half3 envColor = Unity_GlossyEnvironment(
                    UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
                );
                return half4(envColor, 1.0);
            }
            ENDCG
        }

        // uncomment if shadow casting is unwanted, also remove tag "ForceNoShadowCasting"
        /*Pass
        {
            Tags {"LightMode"="ShadowCaster"}

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_shadowcaster
            #include "UnityCG.cginc"

            struct v2f {
                V2F_SHADOW_CASTER;
            };

            v2f vert(appdata_base v)
            {
                v2f o;
                TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                SHADOW_CASTER_FRAGMENT(i)
            }
            ENDCG
        }*/
    }
}
