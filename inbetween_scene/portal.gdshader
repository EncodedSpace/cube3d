shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform float glow = 10.0;
uniform float speed = 0.18;

uniform float distortion = 0.45;
uniform float line_density = 34.0;

uniform float edge_power = 4.0;

////////////////////////////////////////////////////////////

float hash(vec2 p)
{
    return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);
}

float noise(vec2 p)
{
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

float fbm(vec2 p)
{
    float v=0.0;
    float a=0.5;

    for(int i=0;i<6;i++)
    {
        v+=noise(p)*a;
        p*=2.0;
        a*=0.5;
    }

    return v;
}

////////////////////////////////////////////////////////////

void fragment()
{
    vec2 uv=UV*2.0-1.0;

    //------------------------------------------
    // Polar Space
    //------------------------------------------

    float r=length(uv);

    float ang=atan(uv.y,uv.x);

    //------------------------------------------
    // Slow rotation
    //------------------------------------------

    ang+=TIME*speed*0.4;

    //------------------------------------------
    // Polar distortion
    //------------------------------------------

    ang+=sin(r*9.0-TIME*0.7)*0.18;

    uv=vec2(cos(ang),sin(ang))*r;

    //------------------------------------------
    // First Warp
    //------------------------------------------

    vec2 warp;

    warp.x=fbm(uv*3.0+TIME*speed);
    warp.y=fbm(uv*3.0-TIME*speed);

    //------------------------------------------
    // Second Warp
    //------------------------------------------

    vec2 warp2;

    warp2.x=fbm(uv*7.0+warp*2.0);
    warp2.y=fbm(uv*7.0-warp*2.0);

    uv+=(warp-.5)*distortion;

    uv+=(warp2-.5)*distortion*0.6;

    //------------------------------------------
    // Flow Field
    //------------------------------------------

    float flow=fbm(uv*3.5);

    //------------------------------------------
    // Topographic lines
    //------------------------------------------

    float lineA=abs(fract(flow*line_density)-.5);

    lineA=smoothstep(.05,0.0,lineA);

    //------------------------------------------
    // Black/White dispersion
    //------------------------------------------

    vec2 offset=normalize(uv+0.0001)*0.025;

    float h1=fbm((uv+offset)*3.5);

    float h2=fbm((uv-offset)*3.5);

    float l1=abs(fract(h1*line_density)-.5);

    float l2=abs(fract(h2*line_density)-.5);

    l1=smoothstep(.05,0.0,l1);

    l2=smoothstep(.05,0.0,l2);

    float dispersion=abs(l1-l2);

    //------------------------------------------
    // High frequency ink
    //------------------------------------------

    float ink=pow(fbm(uv*14.0+warp*6.0),6.0);

    //------------------------------------------
    // Radial scan
    //------------------------------------------

    float scan=sin(r*40.0-TIME*2.0);

    scan=pow(max(scan,0.0),8.0);

    //------------------------------------------
    // Breathing core
    //------------------------------------------

    float core=exp(-pow(r*3.0,2.2));

    core*=1.0+0.25*sin(TIME*2.2);

    //------------------------------------------
    // Fresnel
    //------------------------------------------

    float fresnel=pow(
        1.0-max(dot(NORMAL,VIEW),0.0),
        edge_power);

    //------------------------------------------
    // Portal edge
    //------------------------------------------

    float edge=smoothstep(1.0,.72,r);

    //------------------------------------------
    // Spatial cracks
    //------------------------------------------

    float cracks=pow(
        max(0.0,
            sin(ang*24.0+
            fbm(uv*8.0)*6.0)),
        12.0);

    //------------------------------------------
    // Compose
    //------------------------------------------

    float col=0.0;

    col+=lineA*2.0;

    col+=dispersion*1.8;

    col+=ink*1.5;

    col+=scan*0.8;

    col+=core*3.2;

    col+=cracks*1.0;

    col+=fresnel*2.8;

    col*=edge;

    ALBEDO=vec3(0.0);

    EMISSION=vec3(col*glow);

    ALPHA=edge;
}