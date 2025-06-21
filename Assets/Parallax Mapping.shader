Shader "Custom/ParallaxPBR_SpecGloss_AmbientHack"
{
    Properties
    {
        _MainTex         ("Albedo (RGB)",       2D)    = "white" {}
        _SpecMap         ("Specular (RGB)",     2D)    = "white" {}
        _GlossMap        ("Smoothness (R)",     2D)    = "gray"  {}
        _HeightMap       ("Height (R)",         2D)    = "black" {}
        _HeightScale     ("Height Scale", Range(0,0.1)) = 0.02
        _AmbientIntensity("Ambient Intensity",  Range(0,1)  ) = 0.15
    }
    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }

        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #define PI 3.14159265359

            TEXTURE2D(_MainTex);    SAMPLER(sampler_MainTex);
            TEXTURE2D(_SpecMap);    SAMPLER(sampler_SpecMap);
            TEXTURE2D(_GlossMap);   SAMPLER(sampler_GlossMap);
            TEXTURE2D(_HeightMap);  SAMPLER(sampler_HeightMap);
            float _HeightScale;
            float _AmbientIntensity;

            struct appdata
            {
                float4 vertex  : POSITION;
                float2 uv      : TEXCOORD0;
                float3 normal  : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float4 posCS       : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float3 viewDirTS   : TEXCOORD1;
                float3 worldNormal : TEXCOORD2;
                float3 worldPos    : TEXCOORD3;
            };

            v2f vert(appdata IN)
            {
                v2f OUT;
                OUT.posCS = TransformObjectToHClip(IN.vertex);

                // build TBN basis
                float3 Nw = TransformObjectToWorldNormal(IN.normal);
                float3 Tw = TransformObjectToWorldDir(IN.tangent.xyz);
                float3 Bw = cross(Nw, Tw) * IN.tangent.w;

                // store world data
                OUT.worldNormal = Nw;
                OUT.worldPos    = mul(GetObjectToWorldMatrix(), IN.vertex).xyz;

                // view vector in tangent‐space
                float3 Vw     = _WorldSpaceCameraPos - OUT.worldPos;
                OUT.viewDirTS = float3(dot(Vw, Tw), dot(Vw, Bw), dot(Vw, Nw));

                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(v2f IN) : SV_Target
            {
                // 1) Parallax UV manip
                float3 vdir = normalize(IN.viewDirTS);
                float  h    = _HeightMap.Sample(sampler_HeightMap, IN.uv).r;
                float2 off  = vdir.xy * (h * _HeightScale) / max(vdir.z, 0.001);
                float2 uvP  = IN.uv + off;

                // 2) Sample maps
                float3 baseCol = _MainTex.Sample(sampler_MainTex, uvP).rgb;
                float3 specCol = _SpecMap.Sample(sampler_SpecMap, uvP).rgb;
                float  smooth  = _GlossMap.Sample(sampler_GlossMap, uvP).r;

                //mesh normal
                float3 N = normalize(IN.worldNormal);

                // 4) Main light + half‐vector
                float3 P    = IN.worldPos;
                float3 V    = normalize(_WorldSpaceCameraPos - P);
                float3 L    = normalize(_MainLightPosition.xyz);
                float3 H    = normalize(L + V);
                float3 Lcol = _MainLightColor.rgb;

                // 5) diffuse
                float NdotL  = saturate(dot(N, L));
                float3 diffD = baseCol * Lcol * NdotL;

                // specular (Blinn + Schlick)
                float NdotV    = saturate(dot(N, V));
                float3 F0      = specCol;
                float3 F       = F0 + (1 - F0) * pow(1 - NdotV, 5);
                float shininess= lerp(4, 256, smooth);
                float NdotH    = saturate(dot(N, H));
                float3 D       = pow(NdotH, shininess) * (shininess + 2) / (8 * PI);
                float3 specD   = Lcol * F * D;

                // 7) Simple ambient 
                float3 ambient = baseCol * _AmbientIntensity;

                float3 color = diffD + specD + ambient;
                return half4(color, 1);
            }
            ENDHLSL
        }
    }
    FallBack "Diffuse"
}
