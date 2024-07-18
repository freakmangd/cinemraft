#version 330

layout(location = 0) in uint vertexInfo;
// in uint vertexPosition;
// in uint vertexNormal;
layout(location = 1) in vec2 vertexTexCoord;

out vec2 fragTexCoord;
out vec4 vBrightness;

uniform mat4 mvp;

void main()
{
    float vertexX = float(vertexInfo & 0xFFu) * 8.0;
    float vertexY = float((vertexInfo >> 8) & 0xFFu) * 8.0;
    float vertexZ = float((vertexInfo >> 16) & 0xFFu) * 8.0;
    uint vertexNormal = (vertexInfo >> 24) & 0xFFu;

    switch (vertexNormal) {
    case 0u:
        vBrightness = vec4(1.0, 1.0, 1.0, 1.0);
        break;
    case 1u:
        vBrightness = vec4(0.25, 0.25, 0.25, 1.0);
        break;
    case 2u:
        vBrightness = vec4(0.75, 0.75, 0.75, 1.0);
        break;
    case 3u:
        vBrightness = vec4(0.75, 0.75, 0.75, 1.0);
        break;
    default:
        vBrightness = vec4(0.5, 0.5, 0.5, 1.0);
        break;
    }

    fragTexCoord = vertexTexCoord;
    gl_Position = mvp*vec4(vertexX, vertexY, vertexZ, 1.0);
}
