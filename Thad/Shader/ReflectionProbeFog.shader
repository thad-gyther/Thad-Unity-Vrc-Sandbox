Shader "Thad/ReflectionProbeFog"
{
    Properties
    {
        [Header(put material on a cube that matches the probe bounds)]
        [Header(or another convex shape that does not exceed the probe bounds)]
        [Header(your room should align as much as possible with the box shaped probe bounds)]
        [Space(20)]
        _Density ("Density", Float) = 0.1
        _Power ("Power", Float) = 2.0
        _Addition ("Addition", Float) = 1.0
        _Absorbtion ("Absorbtion", Float) = 1.0
        _BaseDistance ("Base Distance", Range(0.1, 2)) = 0.4
        [IntRange]_StartMip ("Start Mip (at base distance)", Range(0,4)) = 1.0
        [Toggle(_FIXED_MIP)] _FIXED_MIP ("Fix Mip to Start Mip", Float) = 0
        [Toggle(_IGNORE_DEPTH)] _IGNORE_DEPTH ("Ignore Depth", Float) = 0
        [IntRange]_StencilRef("Stencil Reference", Range(1,255)) = 128
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue" = "Transparent+2"
            "ForceNoShadowCasting" = "True"
            "IgnoreProjector" = "True"
            "DisableBatching" = "True"
        }
        LOD 100

        Pass
        {
            Cull Back
            ColorMask 0
            ZWrite Off
            ZTest LEqual
            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Keep
                zFail Replace
            }
        }

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            Blend One OneMinusSrcAlpha, Zero One
            Cull Front
            ZWrite Off
            ZTest Always
            Stencil
            {
                Ref [_StencilRef]
                Comp NotEqual
                Fail Zero
            }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #pragma shader_feature_local _IGNORE_DEPTH
            #pragma shader_feature_local _FIXED_MIP

            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            struct appdata
            {
                float4 vertex : POSITION;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD0;
                #if !_IGNORE_DEPTH
                    float4 screenPos : TEXCOORD1;
                #endif

                UNITY_VERTEX_OUTPUT_STEREO
            };

            half _Density;
            half _StartMip;
            half _BaseDistance;
            half _Power;
            half _Addition;
            half _Absorbtion;
            float _VRChatMirrorMode;

            #if !_IGNORE_DEPTH
                UNITY_DECLARE_DEPTH_TEXTURE( _CameraDepthTexture );
            #endif

            inline bool isReflectionProbe()
            {
                // according to https://discussions.unity.com/t/reflection-probes-and-shaders/651175/9
                return unity_CameraProjection._m11 == 1 && UNITY_MATRIX_P._m00 == 1;
            }

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

            inline half3 SampleProbe(float3 cubeMapDir, float mip)
            {
                half4 probeData = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, cubeMapDir, mip);
                return DecodeHDR (probeData, unity_SpecCube0_HDR);
            }


            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));//UnityObjectToClipPos(v.vertex);
                o.worldPos = worldPos;

                #if !_IGNORE_DEPTH
                    o.screenPos = ComputeScreenPos(o.vertex);
                #endif

                return o;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                float3 worldViewDir = i.worldPos - _WorldSpaceCameraPos;
                float distance = length(worldViewDir);
                worldViewDir /= distance;

                float boxDistance;
                float3 cubeMapDir = BoxProjectedCubemapDirection2(
                    worldViewDir, _WorldSpaceCameraPos.xyz, unity_SpecCube0_ProbePosition, unity_SpecCube0_BoxMin, unity_SpecCube0_BoxMax, boxDistance
                );

                #if !_IGNORE_DEPTH
                    UNITY_FLATTEN
                    if (_VRChatMirrorMode <= 0.0 && !isReflectionProbe())
                    {
                        float screenDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)));
                        float fragmentDepth = LinearEyeDepth(i.screenPos.z / i.screenPos.w);
                        float depthRatio = screenDepth / fragmentDepth;
                        distance = min(distance, distance * depthRatio);
                    }
                    else
                    {
                        distance = boxDistance;
                    }
                #endif

                float fogIntensity = pow(_Density * distance, _Power);

                #if _FIXED_MIP
                    half3 color = SampleProbe(cubeMapDir, _StartMip);
                    color *= fogIntensity;
                #else
                    float distanceOffset = boxDistance - distance;
                    float mipFactor = _BaseDistance / pow(2.0, _StartMip);
                    float currentDistance = _BaseDistance;
                    float currentMip = _StartMip;
                    //float lastDistance = 0.0;
                    float totalWeight = 0.0;
                    half3 color = 0.0;

                    bool needsInitialStep = distanceOffset > _BaseDistance;
                    UNITY_BRANCH if (needsInitialStep)
                    {
                        currentDistance = distanceOffset;
                        currentMip = log2(distanceOffset / mipFactor);
                        float nextMip = ceil(currentMip);
                        half3 probeColor = SampleProbe(cubeMapDir, currentMip);
                        float weight = nextMip - currentMip;
                        color += probeColor * weight;
                        totalWeight += weight;
                        currentMip = nextMip;
                        currentDistance = pow(2.0, currentMip) * mipFactor;
                    }

                    bool needsMoreSteps = currentDistance <= distance;
                    bool needsFinalStep = needsMoreSteps || !needsInitialStep;
                    while (needsMoreSteps)
                    {
                        half3 probeColor = SampleProbe(cubeMapDir, currentMip);
                        color += probeColor;// * (currentDistance - lastDistance);
                        //lastDistance = currentDistance;
                        currentMip += 1;
                        currentDistance *= 2.0;
                        totalWeight += 1.0;
                        needsMoreSteps = currentDistance <= distance;
                    }
                    needsFinalStep = needsFinalStep && currentDistance > distance;
                    if (needsFinalStep)
                    {
                        currentDistance = distance;
                        currentMip = log2(distance / mipFactor);
                        float weight = currentMip > _StartMip ? frac(currentMip) : 1.0;
                        currentMip = max(_StartMip, currentMip);
                        half3 probeColor = SampleProbe(cubeMapDir, currentMip);
                        //color += probeColor * (currentDistance - lastDistance);
                        color += probeColor * weight;
                        totalWeight += weight;
                    }

                    color *= fogIntensity / totalWeight;//max(1.0, currentMip - _StartMip);
                #endif

                //color /= distance;
                //color *= distance * 0.1;


                return half4(color * _Addition, min(1.0, _Absorbtion * fogIntensity));
            }
            ENDCG
        }
    }
}
