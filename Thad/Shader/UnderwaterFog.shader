Shader "Thad/UnderwaterFog"
{
    Properties
    {
        [HDR][Gamma]_ColorLight ("Light Color", Color) = (1,1,1,1)
        _ColorAbsorbtion ("Light Absorbtion Color", Color) = (0.5,0.5,0.5,1)
        _ColorVolume ("Base Volume Color (usually black)", Color) = (0,0,0,1)
        _Opacity ("Overall opacity (usually 1)", Range(0,1)) = 1
        _SurfaceLevel ("Surface Level", Float) = 0.0
        _Clarity ("Clarity", Range(0,1)) = 0.5
        [KeywordEnum(Off, Simple, Full)] _SceneLighting ("Scene Lighting", Float) = 0
        [KeywordEnum(Ignore, Clip, Show)] _AboveSurface ("Above Surface", Float) = 2
        [Toggle(_IGNORE_DEPTH)] _IGNORE_DEPTH ("Ignore Depth", Float) = 0
        [Toggle(_FULLSCREEN_EFFECT)] _FULLSCREEN_EFFECT ("Fullscreen Effect (put on a quad)", Float) = 0
        [Toggle(_IN_BACKGROUND)] _IN_BACKGROUND ("Render in Background", Float) = 0
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Transparent"
            "Queue" = "Transparent-2"
            "ForceNoShadowCasting" = "True"
            "IgnoreProjector" = "True"
        }
        LOD 100

        Pass
        {
            Tags { "LightMode" = "ForwardBase" }

            Blend One OneMinusSrcAlpha, Zero One
            Cull Back
            ZWrite Off
            ZTest LEqual

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 5.0

            #pragma multi_compile_local _SCENELIGHTING_OFF _SCENELIGHTING_SIMPLE _SCENELIGHTING_FULL
            #pragma multi_compile_local _ABOVESURFACE_IGNORE _ABOVESURFACE_CLIP _ABOVESURFACE_SHOW
            #pragma shader_feature_local _IGNORE_DEPTH
            #pragma shader_feature_local _FULLSCREEN_EFFECT
            #pragma shader_feature_local _IN_BACKGROUND

            #include "UnityCG.cginc"

            #if !_SCENELIGHTING_OFF
                #include "Lighting.cginc"
            #endif

            struct appdata
            {
                float4 vertex : POSITION;
                #if _FULLSCREEN_EFFECT
                    float2 uv :TEXCOORD0;
                #endif

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                #if !_IGNORE_DEPTH
                    float4 screenPos : TEXCOORD0;
                #endif
                #if _FULLSCREEN_EFFECT
                    float3 worldViewDir : TEXCOORD1;
                    #if !_IGNORE_DEPTH
                        float3 viewPos : TEXCOORD2;
                    #endif
                #else
                    float3 worldPos : TEXCOORD1;
                #endif

                UNITY_VERTEX_OUTPUT_STEREO
            };

            half3 _ColorLight;
            half3 _ColorAbsorbtion;
            half3 _ColorVolume;
            half _Opacity;
            float _SurfaceLevel;
            float _Clarity;
            float _VRChatMirrorMode;

            #if !_IGNORE_DEPTH
                UNITY_DECLARE_DEPTH_TEXTURE( _CameraDepthTexture );
            #endif

            v2f vert (appdata v)
            {
                v2f o;

                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                #if _FULLSCREEN_EFFECT
                    float2 clipCoord = v.uv * 2.0 - 1.0;
                    #if UNITY_UV_STARTS_AT_TOP
                        clipCoord.y = -clipCoord.y;
                    #endif
                    o.vertex = float4(clipCoord, UNITY_NEAR_CLIP_VALUE, 1.0);
                    float4 viewPos = mul(unity_CameraInvProjection, o.vertex);
                    viewPos /= viewPos.w; // is this necessary?
                    viewPos.y *= _ProjectionParams.x;
                    #if !_IGNORE_DEPTH
                        o.viewPos = viewPos;
                    #endif
                    float3 worldPos = mul(UNITY_MATRIX_I_V, viewPos).xyz;
                    o.worldViewDir = worldPos - _WorldSpaceCameraPos.xyz;
                #else
                    float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                    o.vertex = mul(UNITY_MATRIX_VP, float4(worldPos, 1.0));//UnityObjectToClipPos(v.vertex);
                    o.worldPos = worldPos;
                #endif

                #if !_IGNORE_DEPTH
                    o.screenPos = ComputeScreenPos(o.vertex);
                #endif

                #if _IN_BACKGROUND
                    #if UNITY_REVERSED_Z
                        o.vertex.z = 0.0;
                    #else
                        o.vertex.z = o.vertex.w;
                    #endif
                #endif

                return o;
            }

            // just here for reference, function not used in code anymore
            inline float3 lightIntegral (float3 worldPos, float3 worldViewDir, float distance)
            {
                float3 base = pow(_ColorAbsorbtion.rgb, -worldViewDir.y) * _Clarity;
                return pow(_ColorAbsorbtion.rgb, _SurfaceLevel - worldPos.y) * pow(base, distance) / log(base);
            }

            inline float3 lightIntegralFull(float heightDelta, float3 worldViewDir, float distance)
            {
                // optimized version of
                //   float3 lightAbsorbtion = lightIntegral(worldPos, worldViewDir, distance);
                //   lightAbsorbtion -= lightIntegral(worldPos, worldViewDir, 0.0);
                float3 base = pow(_ColorAbsorbtion.rgb, -worldViewDir.y) * _Clarity;
                float3 lightAbsorbtion = (pow(base, distance) - 1.0) / log(base);
                lightAbsorbtion *= pow(_ColorAbsorbtion.rgb, heightDelta);
                return lightAbsorbtion;
            }

            half4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                #if !_IGNORE_DEPTH
                    float screenDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE_PROJ(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPos)));
                #endif

                #if _FULLSCREEN_EFFECT
                    float3 worldPos = _WorldSpaceCameraPos;
                #else
                    float3 worldPos = i.worldPos;
                #endif

                float heightDelta = _SurfaceLevel - worldPos.y;

                #if _ABOVESURFACE_CLIP
                    clip (heightDelta);
                #endif

                #if _FULLSCREEN_EFFECT
                    float3 worldViewDir = normalize(i.worldViewDir);

                    float distance = _ProjectionParams.z;
                    #if !_IGNORE_DEPTH
                        UNITY_FLATTEN
                        if (_VRChatMirrorMode <= 0.0)
                        {
                            float3 viewPos = i.viewPos * (screenDepth / -i.viewPos.z);
                            distance = length(viewPos);
                        }
                    #endif

                    #if _ABOVESURFACE_SHOW
                        if (heightDelta < 0)
                        {
                            clip (-0.0001 - worldViewDir.y);
                            float toSurface = heightDelta / worldViewDir.y;
                            //worldPos += worldViewDir * toSurface;
                            heightDelta = 0.0;
                            distance -= toSurface;
                            distance = max(0.0, distance);
                        }
                        else //if...
                    #endif
                    if (worldViewDir.y > 0.0)
                    {
                        distance = min(distance, heightDelta / worldViewDir.y);
                    }
                #else
                    float3 worldViewDir = worldPos - _WorldSpaceCameraPos;
                    float startDistance = length(worldViewDir);
                    worldViewDir /= startDistance;

                    float endDistance = _ProjectionParams.z;
                    #if !_IGNORE_DEPTH
                        UNITY_FLATTEN
                        if (_VRChatMirrorMode <= 0.0)
                        {
                            float fragmentDepth = LinearEyeDepth(i.screenPos.z / i.screenPos.w);
                            float depthRatio = screenDepth / fragmentDepth;
                            endDistance = startDistance * depthRatio;
                        }
                    #endif

                    #if _ABOVESURFACE_SHOW
                        if (heightDelta < 0)
                        {
                            clip (-0.0001 - worldViewDir.y);
                            float toSurface = heightDelta / worldViewDir.y;
                            //worldPos += worldViewDir * toSurface;
                            heightDelta = 0.0;
                            startDistance += toSurface;
                            endDistance = max(endDistance, startDistance);
                        }
                        else //if...
                    #endif
                    if (worldViewDir.y > 0.0)
                    {
                        endDistance = min(endDistance, startDistance + (heightDelta / worldViewDir.y));
                    }
                    float distance = endDistance-startDistance;
                #endif

                half3 lightColor = _ColorLight;
                #if !_SCENELIGHTING_OFF
                    // directional light
                    half3 sceneLight = _LightColor0;
                    // consider angle
                    half surfaceAlignment = max(_WorldSpaceLightPos0.y, 0.0); // idk why y component is positive when pointing down
                    sceneLight *= surfaceAlignment;

                    #if _SCENELIGHTING_FULL
                        half viewAlignment = (dot(_WorldSpaceLightPos0.xyz, worldViewDir) + 1.0) * 0.5;
                        sceneLight *= viewAlignment * viewAlignment;

                        // use reflection probe as ambient light
                        Unity_GlossyEnvironmentData envData;
                        envData.roughness = 1.0;
                        envData.reflUVW = float3(0.0, 1.0, 0.0);
                        half3 envColor = Unity_GlossyEnvironment(
                            UNITY_PASS_TEXCUBE(unity_SpecCube0), unity_SpecCube0_HDR, envData
                        );
                        sceneLight += envColor;
                    #endif

                    lightColor *= sceneLight;
                #endif

                float fog = 1.0 - pow(_Clarity, distance);
                half4 color = half4(_ColorVolume.rgb * fog, fog);
                float3 lightAbsorbtion = lightIntegralFull(heightDelta, worldViewDir, distance);
                color.rgb += lightColor * lightAbsorbtion;

                color *= _Opacity;

                return color;
            }
            ENDCG
        }
    }
}
