#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <math.h>
#include <stdbool.h>

#include "../../Sources/TitikPlugins/include/plugin_api.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifndef M_E
#define M_E 2.71828182845904523536
#endif

#define M_TAU 6.28318530717958647692

/* -------------------------------------------------------------------------
 * Tokenizer & Parser Types
 * ------------------------------------------------------------------------- */

typedef enum {
    TOK_EOF = 0,
    TOK_NUMBER,
    TOK_PLUS,
    TOK_MINUS,
    TOK_STAR,
    TOK_SLASH,
    TOK_PERCENT,
    TOK_CARET,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_COMMA,
    TOK_IDENT,
    TOK_ERROR
} TokenType;

typedef struct {
    TokenType type;
    double number_value;
    char ident[64];
} Token;

typedef struct {
    const char *src;
    size_t pos;
    Token current;
    bool has_error;
    bool has_operator_or_func;
    char error_msg[128];
} Parser;

/* -------------------------------------------------------------------------
 * Tokenizer
 * ------------------------------------------------------------------------- */

static void skip_whitespace(Parser *p) {
    while (p->src[p->pos] != '\0' && isspace((unsigned char)p->src[p->pos])) {
        p->pos++;
    }
}

static void next_token(Parser *p) {
    skip_whitespace(p);

    char c = p->src[p->pos];
    if (c == '\0') {
        p->current.type = TOK_EOF;
        return;
    }

    // Number parsing (including decimals e.g. .5 or 3.14 or 1e5)
    if (isdigit((unsigned char)c) || (c == '.' && isdigit((unsigned char)p->src[p->pos + 1]))) {
        char *endptr = NULL;
        double val = strtod(&p->src[p->pos], &endptr);
        if (endptr == &p->src[p->pos]) {
            p->current.type = TOK_ERROR;
            p->has_error = true;
            snprintf(p->error_msg, sizeof(p->error_msg), "Invalid number");
            return;
        }
        p->pos = (size_t)(endptr - p->src);
        p->current.type = TOK_NUMBER;
        p->current.number_value = val;
        return;
    }

    // Identifiers (functions like sqrt, sin, cos; constants like pi, e)
    if (isalpha((unsigned char)c) || (unsigned char)c >= 0x80) {
        // Support UTF-8 for π (0xCF 0x80)
        if ((unsigned char)p->src[p->pos] == 0xCF && (unsigned char)p->src[p->pos + 1] == 0x80) {
            p->pos += 2;
            p->current.type = TOK_IDENT;
            strncpy(p->current.ident, "pi", sizeof(p->current.ident) - 1);
            p->current.ident[sizeof(p->current.ident) - 1] = '\0';
            return;
        }

        // Support UTF-8 × (0xC3 0x97)
        if ((unsigned char)p->src[p->pos] == 0xC3 && (unsigned char)p->src[p->pos + 1] == 0x97) {
            p->pos += 2;
            p->current.type = TOK_STAR;
            p->has_operator_or_func = true;
            return;
        }

        // Support UTF-8 ÷ (0xC3 0xB7)
        if ((unsigned char)p->src[p->pos] == 0xC3 && (unsigned char)p->src[p->pos + 1] == 0xB7) {
            p->pos += 2;
            p->current.type = TOK_SLASH;
            p->has_operator_or_func = true;
            return;
        }

        size_t start = p->pos;
        while (isalnum((unsigned char)p->src[p->pos]) || p->src[p->pos] == '_') {
            p->pos++;
        }
        size_t len = p->pos - start;
        if (len >= sizeof(p->current.ident)) {
            len = sizeof(p->current.ident) - 1;
        }
        for (size_t i = 0; i < len; i++) {
            p->current.ident[i] = (char)tolower((unsigned char)p->src[start + i]);
        }
        p->current.ident[len] = '\0';
        p->current.type = TOK_IDENT;
        return;
    }

    p->pos++;
    switch (c) {
        case '+': p->current.type = TOK_PLUS; p->has_operator_or_func = true; break;
        case '-': p->current.type = TOK_MINUS; p->has_operator_or_func = true; break;
        case '*':
            // Check for ** exponentiation
            if (p->src[p->pos] == '*') {
                p->pos++;
                p->current.type = TOK_CARET;
            } else {
                p->current.type = TOK_STAR;
            }
            p->has_operator_or_func = true;
            break;
        case '/': p->current.type = TOK_SLASH; p->has_operator_or_func = true; break;
        case '%': p->current.type = TOK_PERCENT; p->has_operator_or_func = true; break;
        case '^': p->current.type = TOK_CARET; p->has_operator_or_func = true; break;
        case '(': p->current.type = TOK_LPAREN; break;
        case ')': p->current.type = TOK_RPAREN; break;
        case ',': p->current.type = TOK_COMMA; break;
        default:
            p->current.type = TOK_ERROR;
            p->has_error = true;
            snprintf(p->error_msg, sizeof(p->error_msg), "Unexpected character '%c'", c);
            break;
    }
}

/* -------------------------------------------------------------------------
 * Recursive Descent Grammar Parser
 * ------------------------------------------------------------------------- */

static double parse_expression(Parser *p);

static double parse_primary(Parser *p) {
    if (p->has_error) return 0.0;

    if (p->current.type == TOK_NUMBER) {
        double val = p->current.number_value;
        next_token(p);
        return val;
    }

    if (p->current.type == TOK_LPAREN) {
        next_token(p);
        double val = parse_expression(p);
        if (p->current.type != TOK_RPAREN) {
            p->has_error = true;
            snprintf(p->error_msg, sizeof(p->error_msg), "Missing closing parenthesis");
            return 0.0;
        }
        next_token(p);
        return val;
    }

    if (p->current.type == TOK_IDENT) {
        char name[64];
        strncpy(name, p->current.ident, sizeof(name) - 1);
        name[sizeof(name) - 1] = '\0';
        next_token(p);

        // Constants
        if (strcmp(name, "pi") == 0) {
            p->has_operator_or_func = true;
            return M_PI;
        }
        if (strcmp(name, "e") == 0) {
            p->has_operator_or_func = true;
            return M_E;
        }
        if (strcmp(name, "tau") == 0) {
            p->has_operator_or_func = true;
            return M_TAU;
        }

        // Functions requiring parentheses
        if (p->current.type == TOK_LPAREN) {
            p->has_operator_or_func = true;
            next_token(p);
            double arg1 = parse_expression(p);
            double arg2 = 0.0;
            bool has_arg2 = false;

            if (p->current.type == TOK_COMMA) {
                next_token(p);
                arg2 = parse_expression(p);
                has_arg2 = true;
            }

            if (p->current.type != TOK_RPAREN) {
                p->has_error = true;
                snprintf(p->error_msg, sizeof(p->error_msg), "Missing closing parenthesis in function '%s'", name);
                return 0.0;
            }
            next_token(p);

            // Single argument functions
            if (strcmp(name, "sqrt") == 0) {
                if (arg1 < 0.0) {
                    p->has_error = true;
                    snprintf(p->error_msg, sizeof(p->error_msg), "Domain error: sqrt of negative number");
                    return 0.0;
                }
                return sqrt(arg1);
            }
            if (strcmp(name, "cbrt") == 0) return cbrt(arg1);
            if (strcmp(name, "abs") == 0 || strcmp(name, "fabs") == 0) return fabs(arg1);
            if (strcmp(name, "sin") == 0) return sin(arg1);
            if (strcmp(name, "cos") == 0) return cos(arg1);
            if (strcmp(name, "tan") == 0) return tan(arg1);
            if (strcmp(name, "asin") == 0) {
                if (arg1 < -1.0 || arg1 > 1.0) { p->has_error = true; return 0.0; }
                return asin(arg1);
            }
            if (strcmp(name, "acos") == 0) {
                if (arg1 < -1.0 || arg1 > 1.0) { p->has_error = true; return 0.0; }
                return acos(arg1);
            }
            if (strcmp(name, "atan") == 0) return atan(arg1);
            if (strcmp(name, "log") == 0 || strcmp(name, "ln") == 0) {
                if (arg1 <= 0.0) { p->has_error = true; return 0.0; }
                return log(arg1);
            }
            if (strcmp(name, "log10") == 0) {
                if (arg1 <= 0.0) { p->has_error = true; return 0.0; }
                return log10(arg1);
            }
            if (strcmp(name, "log2") == 0) {
                if (arg1 <= 0.0) { p->has_error = true; return 0.0; }
                return log2(arg1);
            }
            if (strcmp(name, "exp") == 0) return exp(arg1);
            if (strcmp(name, "floor") == 0) return floor(arg1);
            if (strcmp(name, "ceil") == 0) return ceil(arg1);
            if (strcmp(name, "round") == 0) return round(arg1);

            // Two argument functions
            if (strcmp(name, "pow") == 0) {
                return pow(arg1, has_arg2 ? arg2 : 1.0);
            }
            if (strcmp(name, "atan2") == 0) {
                return atan2(arg1, has_arg2 ? arg2 : 1.0);
            }
            if (strcmp(name, "min") == 0) {
                return fmin(arg1, has_arg2 ? arg2 : arg1);
            }
            if (strcmp(name, "max") == 0) {
                return fmax(arg1, has_arg2 ? arg2 : arg1);
            }

            p->has_error = true;
            snprintf(p->error_msg, sizeof(p->error_msg), "Unknown function '%s'", name);
            return 0.0;
        }

        p->has_error = true;
        snprintf(p->error_msg, sizeof(p->error_msg), "Unknown identifier '%s'", name);
        return 0.0;
    }

    p->has_error = true;
    snprintf(p->error_msg, sizeof(p->error_msg), "Unexpected syntax");
    return 0.0;
}

static double parse_unary(Parser *p) {
    if (p->has_error) return 0.0;

    if (p->current.type == TOK_PLUS) {
        next_token(p);
        return +parse_unary(p);
    }
    if (p->current.type == TOK_MINUS) {
        next_token(p);
        return -parse_unary(p);
    }

    return parse_primary(p);
}

static double parse_power(Parser *p) {
    if (p->has_error) return 0.0;

    double base = parse_unary(p);

    if (p->current.type == TOK_CARET) {
        next_token(p);
        double exponent = parse_power(p); // Right-associative
        return pow(base, exponent);
    }

    return base;
}

static double parse_term(Parser *p) {
    if (p->has_error) return 0.0;

    double left = parse_power(p);

    while (p->current.type == TOK_STAR || p->current.type == TOK_SLASH || p->current.type == TOK_PERCENT) {
        TokenType op = p->current.type;
        next_token(p);
        double right = parse_power(p);

        if (op == TOK_STAR) {
            left *= right;
        } else if (op == TOK_SLASH) {
            if (right == 0.0) {
                p->has_error = true;
                snprintf(p->error_msg, sizeof(p->error_msg), "Division by zero");
                return 0.0;
            }
            left /= right;
        } else if (op == TOK_PERCENT) {
            if (right == 0.0) {
                p->has_error = true;
                snprintf(p->error_msg, sizeof(p->error_msg), "Modulo by zero");
                return 0.0;
            }
            left = fmod(left, right);
        }
    }

    return left;
}

static double parse_expression(Parser *p) {
    if (p->has_error) return 0.0;

    double left = parse_term(p);

    while (p->current.type == TOK_PLUS || p->current.type == TOK_MINUS) {
        TokenType op = p->current.type;
        next_token(p);
        double right = parse_term(p);

        if (op == TOK_PLUS) {
            left += right;
        } else {
            left -= right;
        }
    }

    return left;
}

/* -------------------------------------------------------------------------
 * Main Evaluator Entry
 * ------------------------------------------------------------------------- */

static bool evaluate_expression(const char *expr, double *out_val, bool *out_has_op_or_func) {
    if (!expr || *expr == '\0') return false;

    Parser parser;
    memset(&parser, 0, sizeof(parser));
    parser.src = expr;
    parser.pos = 0;
    parser.has_error = false;
    parser.has_operator_or_func = false;

    next_token(&parser);
    if (parser.current.type == TOK_EOF || parser.has_error) {
        return false;
    }

    double result = parse_expression(&parser);

    if (parser.has_error || parser.current.type != TOK_EOF) {
        return false;
    }

    if (isnan(result) || isinf(result)) {
        return false;
    }

    *out_val = result;
    if (out_has_op_or_func) {
        *out_has_op_or_func = parser.has_operator_or_func;
    }
    return true;
}

/* -------------------------------------------------------------------------
 * Titik Plugin Implementation
 * ------------------------------------------------------------------------- */

static int math_init(void) {
    return 0;
}

static int math_query(const char *query_str, TitikPluginItem *out_items, int max_items) {
    if (!query_str || !out_items || max_items <= 0) {
        return 0;
    }

    // Trim leading whitespace
    const char *q = query_str;
    while (*q != '\0' && isspace((unsigned char)*q)) {
        q++;
    }

    if (*q == '\0') {
        return 0;
    }

    const char *expr = q;

    // Check for optional prefixes
    if (*q == '=') {
        expr = q + 1;
    } else if (strncasecmp(q, "!math ", 6) == 0) {
        expr = q + 6;
    } else if (strncasecmp(q, "!calc ", 6) == 0) {
        expr = q + 6;
    } else if (strncasecmp(q, "math ", 5) == 0) {
        expr = q + 5;
    } else if (strncasecmp(q, "calc ", 5) == 0) {
        expr = q + 5;
    } else if (strncasecmp(q, "calculate ", 10) == 0) {
        expr = q + 10;
    }

    while (*expr != '\0' && isspace((unsigned char)*expr)) {
        expr++;
    }

    if (*expr == '\0') {
        return 0;
    }

    double val = 0.0;
    bool has_op_or_func = false;
    if (!evaluate_expression(expr, &val, &has_op_or_func)) {
        return 0;
    }

    TitikPluginItem *item = &out_items[0];
    memset(item, 0, sizeof(*item));

    strncpy(item->id, "titik.math.result", sizeof(item->id) - 1);
    strncpy(item->category, "Calculator", sizeof(item->category) - 1);

    // Format formatted value
    if (fabs(val) < 1e15 && fabs(val - round(val)) < 1e-9) {
        snprintf(item->title, sizeof(item->title), "%lld", (long long)round(val));
    } else {
        snprintf(item->title, sizeof(item->title), "%.10g", val);
    }

    // Subtitle shows the expression and copy action
    snprintf(item->subtitle, sizeof(item->subtitle), "%s  (Enter to copy)", expr);
    snprintf(item->action_payload, sizeof(item->action_payload), "%s", item->title);

    item->score_boost = 500;

    return 1;
}

static int math_execute(const char *item_id, const char *action_payload) {
    (void)item_id;
    if (!action_payload || *action_payload == '\0') {
        return 0;
    }

    // Copy to macOS clipboard using pbcopy
    FILE *pb = popen("pbcopy", "w");
    if (pb != NULL) {
        fputs(action_payload, pb);
        pclose(pb);
        return 0;
    }

    return 1;
}

static void math_shutdown(void) {
    // No persistent allocations to free
}

static const TitikPlugin g_math_plugin = {
    .id = "titik.plugin.math",
    .name = "math",
    .version = "1.0.0",
    .description = "Instant arithmetic, constants, and scientific calculations",
    .short_bang = "calc",
    .init = math_init,
    .query = math_query,
    .execute = math_execute,
    .shutdown = math_shutdown
};

TITIK_PLUGIN_EXPORT const TitikPlugin *titik_plugin_entry(void) {
    return &g_math_plugin;
}
