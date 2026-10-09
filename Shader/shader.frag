#version 330

in vec2 fragTexCoord;
in vec4 fragColor;

out vec4 finalColor;

uniform sampler2D texture0;

uniform vec2 screenSize;
uniform vec2 lightPos;
uniform float uTime;

const vec2 d = vec2(0.0, 1.0);

float rand(float n){return fract(sin(n) * 43758.5453123);}
float rand(vec2 n) { 
	return fract(sin(dot(n, vec2(12.9898, 4.1414))) * 43758.5453);
}

float noise(vec2 p){
	vec2 ip = floor(p);
	vec2 u = fract(p);
	u = u*u*(3.0-2.0*u);
	
	float res = mix(
		mix(rand(ip),rand(ip+vec2(1.0,0.0)),u.x),
		mix(rand(ip+vec2(0.0,1.0)),rand(ip+vec2(1.0,1.0)),u.x),u.y);
	return res*res;
}

float mult_uv(float n) {
    return n;
}

void main() {


    vec4 texel = texture(texture0, fragTexCoord);

    vec2 pixelPos = fragTexCoord * screenSize;
    vec2 offset = normalize(pixelPos - lightPos);
    float dist = distance(pixelPos, lightPos);
    vec2 uv = fragTexCoord.xy / screenSize.xy;
    uv = uv * 2. - 1.;
    uv.x *= screenSize.x / screenSize.y;
    float get_noise = noise(vec2(mult_uv(uv.x)   + uTime * offset.x  , mult_uv(uv.y) + uTime * offset.y )  );
    
    float mult =  sin(uTime * 2.75) * 0.5 + 0.5 ;

    vec3 distorted = vec3(
       texel.rgb * 0.2 + texture(texture0, fragTexCoord + mult * get_noise  * offset ).rgb * 0.8
     
    );

    // Radius of visible area
    float radius = 120.0;

    // Soft edge
    float softness = 10.0;

    float light = smoothstep(
        radius + softness,
        radius,
        dist
    );
    // float mixed_light = mix(0.6 + .4 * sin(uTime * 2.), 1., light);
    vec4 mixed = mix(vec4(distorted, 1.), texel, light);

    finalColor = mixed;
}