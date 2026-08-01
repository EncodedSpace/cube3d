shader_type sky;

group_uniforms Main;

uniform vec3 player_pos = vec3(0.0);

uniform float world_scale = 0.002;

uniform float line_density = 18.0;
uniform float line_speed = 0.15;

uniform float particle_density = 130.0;

uniform float ripple_speed = 0.3;

uniform float glow = 8.0;
uniform float travel_distance;

////////////////////////////////////////////////////////////

float hash(vec2 p){
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);
}

float noise(vec2 p){

    vec2 i=floor(p);
    vec2 f=fract(p);

    float a=hash(i);
    float b=hash(i+vec2(1.0,0.0));
    float c=hash(i+vec2(0.0,1.0));
    float d=hash(i+vec2(1.0,1.0));

    vec2 u=f*f*(3.0-2.0*f);

    return mix(a,b,u.x)
        +(c-a)*u.y*(1.0-u.x)
        +(d-b)*u.x*u.y;
}

float fbm(vec2 p){

    float v=0.0;
    float a=0.5;

    for(int i=0;i<5;i++){

        v+=noise(p)*a;

        p*=2.0;

        a*=0.5;
    }

    return v;
}

////////////////////////////////////////////////////////////

void sky(){

    vec3 dir=normalize(EYEDIR);

    vec2 uv=dir.xz/(abs(dir.y)+0.4);

    //----------------------------------------------------
    // World Offset
    //----------------------------------------------------

    vec2 world_uv = player_pos.xz * world_scale;

    //----------------------------------------------------
    // Flow Field
    //----------------------------------------------------

    vec2 flow = vec2(

        fbm(uv*2.0 + world_uv + TIME*0.05),

        fbm(uv*2.0 - world_uv - TIME*0.05)

    );

    uv += (flow-0.5)*0.6;

    //----------------------------------------------------
    // World Energy
    //----------------------------------------------------

    float energy = fbm(world_uv*4.0);

    energy = mix(0.7,1.4,energy);

    //----------------------------------------------------
    // Topographic Lines
    //----------------------------------------------------

    float h = fbm(uv*2.5 + TIME*line_speed + world_uv);

    float lines = abs(fract(h*line_density*energy)-0.5);

    lines = smoothstep(0.05,0.0,lines);

    //----------------------------------------------------
    // Ripple
    //----------------------------------------------------

    vec2 ripple_center = vec2(

        sin(player_pos.x*0.001),

        cos(player_pos.z*0.001)

    );

    float r = length(uv-ripple_center);

    float ripple = sin(r*28.0-TIME*4.0*ripple_speed);

    ripple = pow(max(ripple,0.0),6.0);

    //----------------------------------------------------
    // Particles
    //----------------------------------------------------

    vec2 g = floor((uv+world_uv)*particle_density);

    float rnd = hash(g);

    float particle = step(0.995,rnd);

    particle *= 0.5+0.5*sin(TIME*8.0+rnd*30.0);

    //----------------------------------------------------
    // Halo
    //----------------------------------------------------

    float halo = pow(max(dir.y,0.0),5.0);

    //----------------------------------------------------
    // Compose
    //----------------------------------------------------

    float col = 0.0;

    col += lines*1.8;

    col += ripple*0.7;

    col += particle*6.0;

    col += halo*0.4;

    col *= energy;

    col *= glow;

    COLOR = vec3(col);
}