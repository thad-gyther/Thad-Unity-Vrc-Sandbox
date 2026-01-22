Shader "Thad/Particle/ReflectionProbeLit"
{
    Properties
    {
        [Header(Color)]
        [Space(10)]
        [Toggle(_ADDITIVE_BLENDING)] _ADDITIVE_BLENDING ("Additive Blending", Float) = 1
        [HDR] [Gamma] _Color ("Color", Color) = (1,1,1,1)
        [HDR] [Gamma] _Emission ("Emission", Color) = (0,0,0,1)
        _MainTex ("Main Texture", 2D) = "white" {}

        [Header(Diffusion)]
        [Space(10)]
        _DistanceScale ("Distance Scale", Float) = 0.5
        _DistancePower ("Distance Power", Float) = 4.0
        _StartMip ("Start Mip", Range(0,4)) = 0.85
        [Toggle(_FIXED_MIP)] _FIXED_MIP ("Fix Mip to Start Mip", Float) = 0

        [Header(Sample Directions)]
        [Space(10)]
        [Toggle(_SAMPLE_VIEW_DIR)] _SAMPLE_VIEW_DIR ("Sample View Direction", Float) = 1
        [Toggle(_SAMPLE_POS_X)] _SAMPLE_POS_X ("Sample Positive X", Float) = 0
        [Toggle(_SAMPLE_NEG_X)] _SAMPLE_NEG_X ("Sample Negative X", Float) = 0
        [Toggle(_SAMPLE_POS_Y)] _SAMPLE_POS_Y ("Sample Positive Y", Float) = 0
        [Toggle(_SAMPLE_NEG_Y)] _SAMPLE_NEG_Y ("Sample Negative Y", Float) = 0
        [Toggle(_SAMPLE_POS_Z)] _SAMPLE_POS_Z ("Sample Positive Z", Float) = 0
        [Toggle(_SAMPLE_NEG_Z)] _SAMPLE_NEG_Z ("Sample Negative Z", Float) = 0

        [Header(Custom Probe Bounds)]
        [Space(10)]
        [Toggle(_CUSTOM_PROBE_BOUNDS)] _CUSTOM_PROBE_BOUNDS ("Use Custom Probe Bounds", Float) = 0
        _CustomProbeBoundsMin ("Custom Bounds Min (World Space)", Vector) = (-10,-10,-10,0)
        _CustomProbeBoundsMax ("Custom Bounds Max (World Space)", Vector) = (10,10,10,0)

        [Header(Fading)]
        [Space(10)]
        [Toggle(_SOFTPARTICLES_ON)] _SoftParticlesEnabled ("Soft Particles", Float) = 0
        _SoftParticlesNearFadeDistance ("Soft Particles Near Fade", Float) = 0
        _SoftParticlesFarFadeDistance ("Soft Particles Far Fade", Float) = 0.5

        [Toggle(_CAMERAFADING_ON)] _CameraFadingEnabled ("Camera Fading", Float) = 0
        _CameraNearFadeDistance ("Camera Near Fade", Float) = 1.0
        _CameraFarFadeDistance ("Camera Far Fade", Float) = 2.0
    }
    SubShader
    {
        Blend One OneMinusSrcAlpha, Zero One
        ZWrite Off

        Tags
        {
            "RenderType"="Transparent"
            "Queue" = "Transparent"
            "ForceNoShadowCasting" = "True"
            "IgnoreProjector" = "True"
        }
        LOD 100

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }
            Cull Off
            ZTest LEqual

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #pragma shader_feature_local _FIXED_MIP
            #pragma shader_feature_local _SAMPLE_VIEW_DIR
            #pragma shader_feature_local _SAMPLE_POS_X
            #pragma shader_feature_local _SAMPLE_NEG_X
            #pragma shader_feature_local _SAMPLE_POS_Y
            #pragma shader_feature_local _SAMPLE_NEG_Y
            #pragma shader_feature_local _SAMPLE_POS_Z
            #pragma shader_feature_local _SAMPLE_NEG_Z
            #pragma shader_feature_local _CUSTOM_PROBE_BOUNDS

            #pragma shader_feature_local _ADDITIVE_BLENDING
            #pragma shader_feature_local _SOFTPARTICLES_ON
            #pragma shader_feature_local _CAMERAFADING_ON

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                half4 color : COLOR;
                float4 vertex : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                #if _SOFTPARTICLES_ON || _CAMERAFADING_ON
                    float4 screenPos : TEXCOORD2;
                #endif

                UNITY_VERTEX_OUTPUT_STEREO
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            half4 _Color;
            half3 _Emission;
            half _Density;
            half _StartMip;
            half _DistanceScale;
            half _DistancePower;
            float _VRChatMirrorMode;

            #if _CUSTOM_PROBE_BOUNDS
                float4 _CustomProbeBoundsMin;
                float4 _CustomProbeBoundsMax;
            #endif

            #if _CAMERAFADING_ON
                half _CameraNearFadeDistance;
                half _CameraFarFadeDistance;
            #endif

            #if _SOFTPARTICLES_ON
                UNITY_DECLARE_DEPTH_TEXTURE( _CameraDepthTexture );
                half _SoftParticlesNearFadeDistance;
                half _SoftParticlesFarFadeDistance;
            #endif

            inline float3 BoxProjectedCubemapDirection2 (float3 cubeMapDir, float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float3 rbmax = (boxMax.xyz - worldPos) / cubeMapDir;
                float3 rbmin = (boxMin.xyz - worldPos) / cubeMapDir;

                float3 rbminmax = (cubeMapDir > 0.0) ? rbmax : rbmin;

                float fa = min(min(rbminmax.x, rbminmax.y), rbminmax.z);

                worldPos -= cubemapCenter.xyz;
                cubeMapDir = worldPos + (cubeMapDir * fa);

                boxDistance = fa;

                return cubeMapDir;
            }

            inline float3 BoxProjectedCubemapDirectionPosX (float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float fa = boxMax.x - worldPos.x;

                worldPos -= cubemapCenter.xyz;
                worldPos.x += fa;

                boxDistance = fa;

                return worldPos;
            }

            inline float3 BoxProjectedCubemapDirectionNegX (float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float fa = boxMin.x - worldPos.x;

                worldPos -= cubemapCenter.xyz;
                worldPos.x += fa;

                boxDistance = -fa;

                return worldPos;
            }

            inline float3 BoxProjectedCubemapDirectionPosY (float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float fa = boxMax.y - worldPos.y;

                worldPos -= cubemapCenter.xyz;
                worldPos.y += fa;

                boxDistance = fa;

                return worldPos;
            }

            inline float3 BoxProjectedCubemapDirectionNegY (float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float fa = boxMin.y - worldPos.y;

                worldPos -= cubemapCenter.xyz;
                worldPos.y += fa;

                boxDistance = -fa;

                return worldPos;
            }

            inline float3 BoxProjectedCubemapDirectionPosZ (float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float fa = boxMax.z - worldPos.z;

                worldPos -= cubemapCenter.xyz;
                worldPos.z += fa;

                boxDistance = fa;

                return worldPos;
            }

            inline float3 BoxProjectedCubemapDirectionNegZ (float3 worldPos, float4 cubemapCenter, float4 boxMin, float4 boxMax, out float boxDistance)
            {
                float fa = boxMin.z - worldPos.z;

                worldPos -= cubemapCenter.xyz;
                worldPos.z += fa;

                boxDistance = -fa;

                return worldPos;
            }

            inline void SampleProbe(float3 cubeMapDir, float distance, inout half3 color, inout half totalWeight)
            {
                #if _FIXED_MIP
                    float mip = _StartMip;
                #else
                    float mip = pow(max(distance, 0.0) * _DistanceScale, _DistancePower) + _StartMip;
                #endif
                half4 probeData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, cubeMapDir, mip);
                color += DecodeHDR (probeData, unity_SpecCube0_HDR);
                totalWeight += 1.0;
            }

            inline float fade(float distance, float near, float far)
            {
                float fadeFactor = distance - near;
                fadeFactor /= far - near;
                return saturate(fadeFactor);
            }

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                o.color = v.color * _Color;

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));
                o.worldPos = worldPos;

                o.uv = TRANSFORM_TEX(v.uv, _MainTex);

                #if _SOFTPARTICLES_ON || _CAMERAFADING_ON
                    o.screenPos = ComputeScreenPos(o.vertex);
                #endif

                return o;
            }

            half4 frag (v2f i, bool isFrontFace : SV_IsFrontFace) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                half totalWeight = 0.0;
                half3 color = 0.0;
                float distance;
                float3 cubeMapDir;

                #if _CUSTOM_PROBE_BOUNDS
                    float4 boxMin = _CustomProbeBoundsMin;
                    float4 boxMax = _CustomProbeBoundsMax;
                #else
                    float4 boxMin = unity_SpecCube0_BoxMin;
                    float4 boxMax = unity_SpecCube0_BoxMax;
                #endif

                #if _SAMPLE_VIEW_DIR
                    cubeMapDir = i.worldPos - _WorldSpaceCameraPos;
                    cubeMapDir = BoxProjectedCubemapDirection2(
                        cubeMapDir, i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                #if _SAMPLE_POS_X
                    cubeMapDir = BoxProjectedCubemapDirectionPosX(
                        i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                #if _SAMPLE_NEG_X
                    cubeMapDir = BoxProjectedCubemapDirectionNegX(
                        i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                #if _SAMPLE_POS_Y
                    cubeMapDir = BoxProjectedCubemapDirectionPosY(
                        i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                #if _SAMPLE_NEG_Y
                    cubeMapDir = BoxProjectedCubemapDirectionNegY(
                        i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                #if _SAMPLE_POS_Z
                    cubeMapDir = BoxProjectedCubemapDirectionPosZ(
                        i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                #if _SAMPLE_NEG_Z
                    cubeMapDir = BoxProjectedCubemapDirectionNegZ(
                        i.worldPos, unity_SpecCube0_ProbePosition, boxMin, boxMax, distance
                    );
                    SampleProbe(cubeMapDir, distance, color, totalWeight);
                #endif

                color *= 1.0 / totalWeight;

                half4 texColor = tex2D(_MainTex, i.uv);
                texColor *= i.color;
                color.rgb += _Emission;
                color *= texColor.rgb;
                float alpha = texColor.a;

                #if _SOFTPARTICLES_ON || _CAMERAFADING_ON
                    float fragmentDepth = LinearEyeDepth(i.screenPos.z / i.screenPos.w);
                    if (_VRChatMirrorMode <= 0.0)
                    {
                #endif
                    #if _CAMERAFADING_ON
                        alpha *= fade(fragmentDepth, _CameraNearFadeDistance, _CameraFarFadeDistance);
                    #endif
                    #if _SOFTPARTICLES_ON
                        float screenDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)));
                        alpha *= fade(screenDepth - fragmentDepth, _SoftParticlesNearFadeDistance, _SoftParticlesFarFadeDistance);
                    #endif
                #if _SOFTPARTICLES_ON || _CAMERAFADING_ON
                    }
                #endif

                color *= alpha;
                #if _ADDITIVE_BLENDING
                    return half4(color, 0.0);
                #else
                    return half4(color, alpha);
                #endif
            }
            ENDCG
        }
    }
}
