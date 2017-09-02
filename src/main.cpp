
#include "general.h"
#include "os_api.h"
#include "renderer.h"
#include "game.h"

#include "stb_image.h"

#define MACH_LEXER_IMPLEMENTATION
#define MACH_LEXER_ENABLE_HTML

#define MACH_LEXER_REPORT_ERROR report_error
void report_error(int err, const char *err_str, int line, int char_num);

#include "lexer.h"
#include "html_parser.h"

const int WINDOW_WIDTH = 1920;
const int WINDOW_HEIGHT = 1080;

float x = 0, y = 0;

Texture *tex = nullptr;
GL_Renderer *renderer = nullptr;
Font *font = nullptr;

struct Html_Phase {
    float text_x = 0;
    float text_y = 0;
    bool centered = false;
    Font *font = nullptr;
};

void render_html_node(Html_Phase *phs, Html *node);

void render_html_center(Html_Phase *phs, Html_Node *n) {
    // if a parent node in the tree is a center tag, we
    // need to avoid turning off centered until we get back up
    // to the parent-most center node
    bool update = !phs->centered;
    phs->centered = true;
    for (int i = 0; i < n->children.count; ++i) {
        auto c = n->children[i];
        render_html_node(phs, c);
    }
    if (update) phs->centered = false;
}

void render_html_node(Html_Phase *phs, Html *node) {
    if (node->type == HTML_TYPE_BARE_WORD) {
        Html_Bare_Word *word = static_cast<Html_Bare_Word *>(node);
        renderer->draw_text(font, word->word, 20, 20);
    } else if (node->type == HTML_TYPE_NODE || node->type == HTML_TYPE_TAG) {
        Html_Node *n = static_cast<Html_Node *>(node);
        // @FixMe Atom table
        if (node->type == HTML_TYPE_TAG && strcmp(static_cast<Html_Tag *>(n)->identifier->name->name, "center") == 0) {
            render_html_center(phs, n);
            return;
        }
        for (int i = 0; i < n->children.count; ++i) {
            auto c = n->children[i];
            render_html_node(phs, c);
        }
    }
}

void render_html_dom(Html_Dom *dom) {
    Html_Phase phs;
    for (int i = 0; i < dom->children.count; ++i) {
        auto c = dom->children[i];
        render_html_node(&phs, c);
    }
}

void render() {
    renderer->start_scene();
    renderer->clear_screen(0.0, 0.0, 0.0, 1.0);
    renderer->set_projection_fov(90.0f, (float)WINDOW_WIDTH/(float)WINDOW_HEIGHT, 0.1f, 100.0f);
    // renderer->draw_cube(0, 0, -2, 1);
    renderer->draw_model(__model);
    renderer->finish_scene();


    renderer->set_projection_ortho(0, (float)WINDOW_WIDTH, (float)WINDOW_HEIGHT, 0, -1, 1);
    Bitmap_Frame frame = {0};
    frame.tex_coords.width = 14.0f / (float)tex->width;
    frame.tex_coords.height = 14.0f / (float)tex->height;
    frame.tex_coords.x = (16.0f * 3) / (float)tex->width;
    frame.tex_coords.y = (16.0f * 4) / (float)tex->height;
    Sprite sp = {0};
    sp.current_frame = &frame;
    sp.dimensions.x = x;
    sp.dimensions.y = y;
    sp.dimensions.width = 100.0;
    sp.dimensions.height = 100.0;
    sp.texture = tex;
    // renderer->draw_sprite(&sp);
    // renderer->draw_text(font, "Hello World!", 32, 32);
    // render_html_dom(dom);
}

#pragma warning(disable:4996)

char *slurp_file(const char *path) {
    FILE *file = fopen(path, "rb");
    if (!file) return nullptr;

    fseek(file, 0, SEEK_END);
    u64 len = ftell(file);
    fseek(file, 0, SEEK_SET);

    char *out = GET_MEMORY_SIZED(len+1);
    size_t count = 0;
    while ((count = fread(out+count, 1, len-count, file)) != 0) {}

    fclose(file);
    out[len] = 0;
    return out;
}

unsigned char ttf_buffer[1<<20];
unsigned char temp_bitmap[512*512];

void my_stbtt_initfont(Font *font)
{
    FILE *f = fopen("c:/windows/fonts/times.ttf", "rb");
    fread(ttf_buffer, 1, 1<<20, f);
    stbtt_BakeFontBitmap(ttf_buffer,0, 32.0, temp_bitmap,512,512, 32,96, font->cdata); // no guarantee this fits!
    fclose(f);
}


typedef Hash_Map<Material *> Material_Lib;

void model_loader_parse_mtl(Game *game, const char *src, Material_Lib &lib, const char *filepath) {
    ML_State st;
    ml_init(&st, strlen(src), (char *)src);
    ML_Token tok;

    Material *mat = nullptr;
    ml_get_token(&st, &tok);
    while(tok.type != ML_TOKEN_END) {
        if (tok.type == '#') {
            int current_line = tok.line_number;
            while (tok.line_number == current_line && tok.type != ML_TOKEN_END)
                ml_get_token(&st, &tok); // eat comment line
            continue;
        }

        if (tok.type == ML_TOKEN_IDENTIFIER) {
            char *ml_string_to_c_string(ML_String *str);
            char *name = ml_string_to_c_string(&tok.string);
            if (compare_c_strings(name, "newmtl")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_IDENTIFIER);
                lib[ml_string_to_c_string(&tok.string)] = mat = GET_MEMORY_ZERO_INIT(Material);

                ml_get_token(&st, &tok);
            } else if (!mat) {
                assert(0 && "setting property before declaring material");
            } else if (compare_c_strings(name, "Ns")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT || tok.type == ML_TOKEN_INTEGER);
                if (tok.type == ML_TOKEN_FLOAT)
                    mat->specular_exp = (float)tok.float64;
                else if (tok.type == ML_TOKEN_INTEGER)
                    mat->specular_exp = (float)tok.integer;
                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "Ka")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float r = (float)tok.float64;
                
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float g = (float)tok.float64;

                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float b = (float)tok.float64;

                Color c;
                c.r = r;
                c.g = g;
                c.b = b;
                mat->ambient = c;

                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "Kd")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float r = (float)tok.float64;
                
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float g = (float)tok.float64;

                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float b = (float)tok.float64;

                Color c;
                c.r = r;
                c.g = g;
                c.b = b;
                mat->diffuse = c;

                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "Ks")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float r = (float)tok.float64;
                
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float g = (float)tok.float64;

                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float b = (float)tok.float64;

                Color c;
                c.r = r;
                c.g = g;
                c.b = b;
                mat->specular = c;

                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "Ke")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float r = (float)tok.float64;
                
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float g = (float)tok.float64;

                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                float b = (float)tok.float64;

                Color c;
                c.r = r;
                c.g = g;
                c.b = b;
                mat->emissive = c;

                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "Ni")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT);
                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "d")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_FLOAT || tok.type == ML_TOKEN_INTEGER);
                if (tok.type == ML_TOKEN_FLOAT)
                    mat->transparency = (float)tok.float64;
                else if (tok.type == ML_TOKEN_INTEGER)
                    mat->transparency = (float)tok.integer;
                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "illum")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_INTEGER);
                ml_get_token(&st, &tok);
            } else {
                assert(0);
            }
        } else {
            assert(0);
        }
    }
}

char *path_of(const char *filepath) {
    const char *p = strrchr(filepath, '/');
    char *out = GET_MEMORY_SIZED(p - filepath + 2);
    memcpy(out, filepath, p-filepath+1);
    out[p-filepath+1] = 0;
    return out;
}

float ml_get_signed_float(ML_State *st, ML_Token *tok) {
    bool neg = false;
    if (tok->type == '-') {
        neg = true;
        ml_get_token(st, tok);
    }

    assert(tok->type == ML_TOKEN_FLOAT);
    float val = (float) tok->float64;

    ml_get_token(st, tok);
    return neg ? -val : val;    
}

Model *model_loader_parse_obj(Game *game, const char *src, const char *obj_filepath) {
    Material_Lib lib;
    ML_State st;
    st.flags = ML_DOTS_IN_IDENTIFIERS;
    ml_init(&st, strlen(src), (char *)src);
    ML_Token tok;

    Model *mod = GET_MEMORY_ZERO_INIT(Model);
    Mesh *mesh = nullptr;
    Array<Vector3> vertices;
    Array<Vector3> normals;
    ml_get_token(&st, &tok);
    while(tok.type != ML_TOKEN_END) {
        if (tok.type == '#') {
            int current_line = tok.line_number;
            while (tok.line_number == current_line && tok.type != ML_TOKEN_END)
                ml_get_token(&st, &tok); // eat comment line
            continue;
        }

        if (tok.type == ML_TOKEN_IDENTIFIER) {
            char *ml_string_to_c_string(ML_String *str);
            char *name = ml_string_to_c_string(&tok.string);
            if (compare_c_strings(name, "mtllib")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_IDENTIFIER);
                char *filepath = ml_string_to_c_string(&tok.string);
                char *p = path_of(obj_filepath);
                filepath = concatenate(p, filepath);
                char *lib_src = slurp_file(filepath);
                model_loader_parse_mtl(game, lib_src, lib, filepath);

                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "o")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_IDENTIFIER);
                mesh = GET_MEMORY_ZERO_INIT(Mesh);
                mod->meshes.add(mesh);
                vertices.clear();

                ml_get_token(&st, &tok);
            } else if (!mesh) {
                assert(0 && "setting property before declaring object");
            } else if (compare_c_strings(name, "v")) {
                ml_get_token(&st, &tok);
                Vector3 v;
                v.x = ml_get_signed_float(&st, &tok);
                v.y = ml_get_signed_float(&st, &tok);
                v.z = ml_get_signed_float(&st, &tok);
                vertices.add(v);
            } else if (compare_c_strings(name, "vn")) {
                ml_get_token(&st, &tok);
                Vector3 v;
                v.x = ml_get_signed_float(&st, &tok);
                v.y = ml_get_signed_float(&st, &tok);
                v.z = ml_get_signed_float(&st, &tok);
                normals.add(v);
            } else if (compare_c_strings(name, "usemtl")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_IDENTIFIER);
                char *mtl_name = ml_string_to_c_string(&tok.string);
                mesh->material = lib[mtl_name];
                assert(mesh->material);
                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "s")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_IDENTIFIER);
                // smooth shading
                ml_get_token(&st, &tok);
            } else if (compare_c_strings(name, "f")) {
                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_INTEGER);
                mesh->vertices.add(vertices[tok.integer-1]);
                ml_get_token(&st, &tok); assert(tok.type == '/');
                ml_get_token(&st, &tok);
                if (tok.type == ML_TOKEN_INTEGER) {
                    // mesh->tex_coords
                    ml_get_token(&st, &tok);
                }
                assert(tok.type == '/');
                ml_get_token(&st, &tok); assert(tok.type == ML_TOKEN_INTEGER);
                mesh->normals.add(normals[tok.integer-1]);

                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_INTEGER);
                mesh->vertices.add(vertices[tok.integer-1]);
                ml_get_token(&st, &tok); assert(tok.type == '/');
                ml_get_token(&st, &tok);
                if (tok.type == ML_TOKEN_INTEGER) {
                    // mesh->tex_coords
                    ml_get_token(&st, &tok);
                }
                assert(tok.type == '/');
                ml_get_token(&st, &tok); assert(tok.type == ML_TOKEN_INTEGER);
                mesh->normals.add(normals[tok.integer-1]);

                ml_get_token(&st, &tok);
                assert(tok.type == ML_TOKEN_INTEGER);
                mesh->vertices.add(vertices[tok.integer-1]);
                ml_get_token(&st, &tok); assert(tok.type == '/');
                ml_get_token(&st, &tok);
                if (tok.type == ML_TOKEN_INTEGER) {
                    // mesh->tex_coords
                    ml_get_token(&st, &tok);
                }
                assert(tok.type == '/');
                ml_get_token(&st, &tok); assert(tok.type == ML_TOKEN_INTEGER);
                mesh->normals.add(normals[tok.integer-1]);

                ml_get_token(&st, &tok);
            } else {
                assert(0);
            }
        } else {
            assert(0);
        }
    }
    return mod;
}

struct Asset_Manager {
    Hash_Map<Texture *> textures;
    Hash_Map<Model *> models;
    Hash_Map<Material_Lib *> materials;
    Hash_Map<Font *> fonts;

    Game *game;

    Asset_Manager(Game *g) : game(g) {}

    Texture *load_image(const char *filepath) {
        int width, height, comp;
        unsigned char *data = stbi_load(filepath, &width, &height, &comp, 4); // 4 forces RGBA components / 4 bytes-per-pixel
        if (data) {
            Texture *tex = textures[filepath];
            if (!tex) {
                tex = GET_MEMORY(Texture);
                textures[filepath] = tex;
            } else {
                game->renderer->delete_texture(tex);
            }

            game->renderer->create_texture(tex, width, height, data);
            stbi_image_free(data);
            return tex;
        }

        printf("ERROR:%s\n", stbi_failure_reason());
        return nullptr;
    }

    Model *load_model(const char *filepath) {
        char *obj_source = slurp_file(filepath);
        return model_loader_parse_obj(game, obj_source, filepath);
    }
};

void file_update_callback(File_Notification *notif, void *userdata) {
    Game *g = (Game *)userdata;
    printf("CALLBACK %s\n", &notif->name[0]);
    if (g->asset_man->textures.contains_key(&notif->name[0])) {
        printf("Updating file: %s\n", &notif->name[0]);
        g->asset_man->load_image(notif->name);
    } else {
        printf("No key for %s\n", &notif->name[0]);
    }
}


#include <string.h>
#include <stdio.h>
void report_error(int err, const char *err_str, int line, int char_num) {
    printf("Error:%d:%d: %s\n", line, char_num, err_str);
}

void Game::report_error(char *format, ...) {
    assert(0);
}

void print_token(ML_Token *tok) {
    printf("%d:%d: ", tok->line_number, tok->character_number);
    switch(tok->type) {
        case ML_TOKEN_UNINITIALIZED:
            printf("Uninitialized token\n");
            break;
        case ML_TOKEN_STRING:
            printf("string: \"%.*s\"\n", (int)tok->string.length, tok->string.data);
            break;
        case ML_TOKEN_HTML_COMMENT:
            printf("<!\n");
            break;
        case ML_TOKEN_IDENTIFIER:
            printf("ident: \"%.*s\"\n", (int)tok->string.length, tok->string.data);
            break;
        case ML_TOKEN_INTEGER:
            printf("int: %llu\n", tok->integer);
            break;
        case ML_TOKEN_FLOAT:
            printf("float: %f\n", tok->float64);
            break;
        default:
            printf("tok: '%c'\n", tok->type);
    }
}

int main(int argc, char **argv) {
    os_init_platform();
    setcwd(os_get_executable_path());
    // os_watch_dir("assets");

    OS_Window win = os_create_window(WINDOW_WIDTH, WINDOW_HEIGHT, "test");
    OS_GL_Context ctx = os_create_gl_context(win);
    os_make_current(win, ctx);
    os_set_vsync(true);

    GL_Renderer rdr;
    rdr.init(WINDOW_WIDTH, WINDOW_HEIGHT);
    renderer = &rdr;
    Game game;
    Asset_Manager asset_man (&game);
    game.renderer = &rdr;
    game.asset_man = &asset_man;

    Font fnt;
    my_stbtt_initfont(&fnt);
    rdr.create_font(&fnt, 512, 512, &temp_bitmap[0]);
    font = &fnt;

    __model = asset_man.load_model("assets/monkey.obj");

    while (true) {
        bool exit = false;

        for (int i = 0; i < input_events.count; ++i) {
            Input_Event &ev = input_events[i];
            if (ev.type == Event_Type::QUIT) {
                exit = true;
            } else if (ev.type == Event_Type::MOUSE_BUTTON) {
               
            } else if (ev.type == Event_Type::KEYBOARD) {
                
            }
        }

        if (joysticks.count) {
            auto &joy = joysticks[0];
            x += joy.left_thumb.x;
            y -= joy.left_thumb.y;

            if (joy.buttons & JOYSTICK_BUTTON_BACK) exit = true;
        }

        if (exit) break;

        if (file_changes.count) Sleep(10);
        for (int i = 0; i < file_changes.count; ++i) {
            auto &it = file_changes[i];
            file_update_callback(&it, &game);
        }

        render();

        os_swap_buffers(win);
        os_pump_input();

        // @Note we have to wait long enough for whatever program is
        // changing our file to release its handle in order for us
        // to reload it
        os_pump_file_notifications(file_update_callback, &game);
    }

    os_close_window(win);
    return 0;
}
