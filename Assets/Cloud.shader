// Upgrade NOTE: replaced '_Object2World' with 'unity_ObjectToWorld'

Shader "Unlit/Cloud"
{
	Properties{
		_MainTex("Base (RGB)", 2D) = "white" {}

	}
	SubShader
	{
		// queue defines in which order this is drawn
		// transparent materials are drawn after opaque ones

		// render type classifies the shader? useful for depth calculation?
		Tags {"Queue" = "Transparent" "RenderType" = "Transparent"}
		// how computationally demanding shader is, so unity can ignore subshaders above certain lod when told
		LOD 100
		// premultiplied alpha
		//    sourcefactor * generated color + destinationfactor * back color
		//   srcfct	dstfct
		Blend One OneMinusSrcAlpha 
		// no cull  no write to depth   always draw objects irrespective of depth
		Cull Off ZWrite Off Ztest Always
		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			static float SCATTERING = 4.0;
			static float ABSORTION = 0.01;
			static float EXTINCTION = SCATTERING + ABSORTION;
			static float3 LIGHT_DIRECTION = { 0.0, -1.0, 0.0 };

			sampler2D _MainTex;

			float remap(float value, float startMin, float startMax, float endMin, float endMax) {
				return endMin + (value - startMin) / (startMax - startMin) * (endMax - endMin);
			}

			float2 oBBDistance(float3 rayOrigin, float3 rayDirection) {
				float3 boxMax = {1.0, 1.0, 1.0};
				float3 boxMin = {-1.0, -1.0, -1.0};
				float3 collisions1 = (boxMin - rayOrigin) / rayDirection;
				float3 collisions2 = (boxMax - rayOrigin) / rayDirection;
				float3 maxCollisions = max(collisions1, collisions2);
				float3 minCollisions = min(collisions1, collisions2);
				float biggestMin =  max(max(minCollisions.x, minCollisions.y), minCollisions.z);
				float smallestMax = min(min(maxCollisions.x, maxCollisions.y), maxCollisions.z);
				// if there is no overlapping, there is no collision
				// if(biggestMin < smallestMax)
				//	return -1.0;
				float2 distances = 0;
				distances.x = max(0, biggestMin);
				distances.y = max(0, smallestMax - distances.x);
				return distances;
			}
			static float PI = 3.1416;
			float henyeyGreenstein(float g, float cosT) {
				return (1.0 / 4.0 * PI) * (1.0 - pow(g, 2.0)) / pow(1.0 + pow(g, 2.0) - 2.0 * g * cosT, (3.0 / 2.0));
			}

			float phase(float cosT) {
				// slides with 0.6 forward only initially
				//return henyeyGreenstein(0.6, cosT);
				//         forward scattering		    backward scattering
				return max(henyeyGreenstein(0.3, cosT), henyeyGreenstein(-0.2, cosT));
			}

			float beerLambert(float extinction, float density) {
				return exp(-extinction * density);
			}
			static float3 origin = { 0.0, 0.0, 0.0 };
			float sampleDensity(float3 p){
				float density = 0.5;
				if(p.y < 0.5 && p.y > 0)
					return density;// min(1.0, remap(p.y, 0, 0.5, 0, 1));// * remap(p.y, 0.3, 0.5, 1, 0));
				return 0.0;

				float3 fo = p - origin;
				float a = (fo.x * fo.x / 0.8 + fo.y * fo.y / 0.2 + fo.z * fo.z / 0.3 > 1.0 ? 0.0 : density);
				float b = (fo.x * fo.x + fo.y * fo.y / 0.01 + fo.z * fo.z / 0.7 > 1.0 ? 0.0 : 0.2);
				float c = (fo.x * fo.x + fo.y * fo.y + fo.z * fo.z > 1.0 ? 0.0 : density);
				float d = (fo.x * fo.x / 0.3 + fo.y * fo.y / 0.2 + fo.z * fo.z / 0.8 > 1.0 ? 0.0 : density);
				return c;//max(a, b);// + b;
			}

			float integrateLight(float3 rayOrigin, float3 rayDirection) {
				float3 point1 = { 0.0, 0.1, 0.0 };
				float3 point2 = { 0.0, 0.2, 0.0 };
				float3 point3 = { 0.0, 0.3, 0.0 };
				float3 point4 = { 0.0, 0.4, 0.0 };
				float3 point5 = { 0.0, 3.0, 0.0 };
				float density1 = sampleDensity(rayOrigin + point1);
				float density2 = sampleDensity(rayOrigin + point2);
				float density3 = sampleDensity(rayOrigin + point3);
				float density4 = sampleDensity(rayOrigin + point4);
				float density5 = sampleDensity(rayOrigin + point5);
				float density = density1 + density2 + density3 + density4 + density5;
				density /= 5;
				//return 0.2;
				//return beerLambert(EXTINCTION, -rayOrigin.y * 0.1);
				//return density < 0.8? 5.0 : 0.0;
				// 1  KEK
				return beerLambert(EXTINCTION, density);
			}

			float2 integrateVolume(float distanceToOBB, float distanceInsideOBB, float stepSize, float3 rayOrigin, float3 rayDirection) {
				// non-emissive
				float light = 0.0;
				// phase(li ->, <- vi) == -1, but should be 1
				// phase(cos(x)) is like e^x, so bigger in positives and smaller in negatives
				float cosT = -dot(rayDirection, LIGHT_DIRECTION); 
				float scattering = phase(cosT);
				float lastTransmittance = 0.0;
				float accumExtinction = 1.0;
				float accumDensity = 0.0;
				float3 currentPoint;
				float density;
				int hitLimit = 100000;
				int hits = 0;
				for (float i = 0.0;  i < distanceInsideOBB; i += stepSize) {
					currentPoint = rayOrigin + rayDirection * (distanceToOBB + i);
					density = sampleDensity(currentPoint);
					if (density > 0 && hits < hitLimit) {
						hits++;
						accumDensity +=  density * stepSize;
						// 50 KEK
						lastTransmittance = beerLambert(EXTINCTION, accumDensity);
						//accumExtinction *= exp(-pe* density * stepSize); 
						light += lastTransmittance * SCATTERING * integrateLight(currentPoint, -LIGHT_DIRECTION) * phase(cosT) * stepSize;
						if(light >= 0.99)
							break;
					}	
				}
				float2 r;
				r.x = light;
				r.y = lastTransmittance;
				return r;
				
			}			

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f
			{
				float4 position : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 worldPosition : TEXCOORD2;
			};

			v2f vert(appdata v)
			{
				v2f o;
				// Vertex shader output
				o.position = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				// UnityWorldSpaceViewDir computes vector from vertex to camera
				// Pass it to TEXCOORD0 to interpolate it along the triangle
				o.worldPosition = mul(v.vertex, unity_ObjectToWorld);
				return o;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				//put transmittance on light integrator!
				// Get the ray data for this specific fragment
				
				float3 rayOrigin = _WorldSpaceCameraPos;
				float3 rayDirection = normalize(i.worldPosition - _WorldSpaceCameraPos);
				float2 oBBDistances = oBBDistance(rayOrigin, rayDirection);
				//fixed4 color = tex2D(_MainTex, i.uv);
				float2 wea = integrateVolume(oBBDistances.x, oBBDistances.y, 0.001, rayOrigin, rayDirection);
				//fixed4 color = { wea, wea, wea, 1 };
				fixed4 color = 0;// tex2D(_MainTex, i.uv);
				// light in volume + color at end of ray * transmittance of whole volume
			
				color.r = wea.x;
				color.g = wea.x;
				color.b = wea.x;
				return color;
			}
			ENDCG
		}
	}
}
