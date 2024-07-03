#version 330       

in vec2 fragTexCoord;              
in vec4 vBrightness;

out vec4 finalColor;               

uniform sampler2D texture0;        
uniform vec4 colDiffuse;           

void main()                        
{                                  
    vec4 texelColor;
    //vec4 texelColor = texture(texture0, fragTexCoord);
    if (fragTexCoord.x < 0) {
        uint bits = floatBitsToUint(fragTexCoord.y);
        uint r = bits & 0xFFu;
        uint g = (bits >> 8) & 0xFFu;
        uint b = (bits >> 16) & 0xFFu;
        texelColor = vec4(float(r) / 255.0, float(g) / 255.0, float(b) / 255.0, 1.0);
    } else {
        texelColor = texture(texture0, fragTexCoord);
    }
    finalColor = vBrightness*texelColor*colDiffuse;
}
