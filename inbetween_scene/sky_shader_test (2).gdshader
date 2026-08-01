shader_type sky;

group_uniforms Main;

uniform float line_density = 18.0;
uniform float line_speed = 0.15;
uniform float particle_density = 130.0;
uniform float ripple_speed = 0.3;
uniform float glow = 8.0;

////////////////////////////////////////////////////////////

float hash(vec2 p){
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float noise(vec2 p){

    vec2 i=floor(p);
    vec2 f=fract(p);

    float a=hash(i);
    float b=hash(i+vec2(1,0));
    float c=hash(i+vec2(0,1));
    float d=hash(i+vec2(1,1));

    vec2 u=f*f*(3.0-2.0*f);

    return mix(a,b,u.x)
        +(c-a)*u.y*(1.0-u.x)
        +(d-b)*u.x*u.y;
}

float fbm(vec2 p){

    float f=0.0;

    float a=0.5;

    for(int i=0;i<5;i++){

        f+=noise(p)*a;

        p*=2.0;

        a*=0.5;
    }

    return f;
}

////////////////////////////////////////////////////////////

void sky(){

    vec3 dir=normalize(EYEDIR);

    vec2 uv=dir.xz/(abs(dir.y)+0.4);

    //----------------------------------------------------
    // Flow Field
    //----------------------------------------------------

    vec2 flow=vec2(

        fbm(uv*2.0+TIME*0.05),

        fbm(uv*2.0-TIME*0.05)

    );

    uv+=flow*0.4;

    //----------------------------------------------------
    // Topographic Lines
    //----------------------------------------------------

    float h=fbm(uv*2.5+TIME*line_speed);

    float lines=abs(fract(h*line_density)-0.5);

    lines=smoothstep(0.05,0.0,lines);

    //----------------------------------------------------
    // Energy Ripple
    //----------------------------------------------------

    float r=length(uv);

    float ripple=sin(r*28.0-TIME*4.0*ripple_speed);

    ripple=pow(max(ripple,0.0),6.0);

    //----------------------------------------------------
    // Digital Particles
    //----------------------------------------------------

    vec2 g=floor(uv*particle_density);

    float rnd=hash(g);

    float particle=step(.995,rnd);

    particle*=0.5+0.5*sin(TIME*8.0+rnd*20.0);

    //----------------------------------------------------
    // Halo
    //----------------------------------------------------

    float halo=pow(max(dir.y,0.0),5.0);

    //----------------------------------------------------
    // Compose
    //----------------------------------------------------

    float col=0.0;

    col+=lines*1.8;

    col+=particle*5.0;

    col+=ripple*0.6;

    col+=halo*0.3;

    col*=glow;

    COLOR=vec3(col);
}