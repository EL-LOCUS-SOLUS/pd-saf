#include <string.h>

#include <m_pd.h>
#include <g_canvas.h>

#include "utilities.h"
#include <sldoa.h>

static t_class *sldoa_tilde_class;

// ─────────────────────────────────────
typedef struct _sldoa_tilde {
    t_object obj;
    t_sample sample;

    void *hAmbi;
    unsigned hAmbiInit;

    t_sample **aIns;
    t_sample **aOuts;
    t_sample **aInsTmp;
    t_sample **aOutsTmp;

    int nAmbiFrameSize;
    int nPdFrameSize;
    int nInAccIndex;
    int nOutAccIndex;

    int nOrder;
    int nIn;
    int nPreviousIn;

    int multichannel;
} t_sldoa_tilde;

// ─────────────────────────────────────
static void sldoa_tilde_malloc(t_sldoa_tilde *x) {
    if (x->aIns) {
        for (int i = 0; i < x->nPreviousIn; i++) {
            if (x->aIns[i]) {
                freebytes(x->aIns[i], x->nAmbiFrameSize * sizeof(t_sample));
            }
            if (x->aInsTmp[i]) {
                freebytes(x->aInsTmp[i], x->nAmbiFrameSize * sizeof(t_sample));
            }
        }
        freebytes(x->aIns, x->nIn * sizeof(t_sample *));
    }

    // memory allocation
    x->aIns = (t_sample **)getbytes(x->nIn * sizeof(t_sample *));
    x->aInsTmp = (t_sample **)getbytes(x->nIn * sizeof(t_sample *));

    for (int i = 0; i < x->nIn; i++) {
        x->aIns[i] = (t_sample *)getbytes(x->nAmbiFrameSize * sizeof(t_sample));
        x->aInsTmp[i] = (t_sample *)getbytes(x->nAmbiFrameSize * sizeof(t_sample));
    }
    x->nPreviousIn = x->nIn;
}

// ─────────────────────────────────────

// ─────────────────────────────────────
static void sldoa_tilde_set(t_sldoa_tilde *x, t_symbol *s, int argc, t_atom *argv) {
    const char *method = s->s_name;
}

// ─────────────────────────────────────
t_int *sldoa_tilde_performmultichannel(t_int *w) {
    t_sldoa_tilde *x = (t_sldoa_tilde *)(w[1]);
    int n = (int)(w[2]);
    t_sample *ins = (t_sample *)(w[3]);

    if (n < x->nAmbiFrameSize) {
        for (int ch = 0; ch < x->nIn; ch++) {
            memcpy(x->aIns[ch] + x->nInAccIndex, ins + (n * ch), n * sizeof(t_sample));
        }
        x->nInAccIndex += n;

        // Process only if a full frame is ready
        if (x->nInAccIndex == x->nAmbiFrameSize) {
            // TODO: process
        }

    } else {
        int chunks = n / x->nAmbiFrameSize;
        for (int chunkIndex = 0; chunkIndex < chunks; chunkIndex++) {
            // Copia os dados de entrada para cada canal
            for (int ch = 0; ch < x->nIn; ch++) {
                memcpy(x->aInsTmp[ch], (t_sample *)w[3] + ch * n + chunkIndex * x->nAmbiFrameSize,
                       x->nAmbiFrameSize * sizeof(t_sample));
            }
        }
    }

    return (w + 4);
}

// ─────────────────────────────────────
t_int *sldoa_tilde_perform(t_int *w) {
    t_sldoa_tilde *x = (t_sldoa_tilde *)(w[1]);
    int n = (int)(w[2]);

    if (n < x->nAmbiFrameSize) {
        for (int ch = 0; ch < x->nIn; ch++) {
            memcpy(x->aIns[ch] + x->nInAccIndex, (t_sample *)w[3 + ch], n * sizeof(t_sample));
        }
        x->nInAccIndex += n;
        if (x->nInAccIndex == x->nAmbiFrameSize) {
            // TODO: process
            x->nInAccIndex = 0;
        }
    } else {
        int chunks = n / x->nAmbiFrameSize;
        for (int chunkIndex = 0; chunkIndex < chunks; chunkIndex++) {
            for (int ch = 0; ch < x->nIn; ch++) {
                memcpy(x->aInsTmp[ch], (t_sample *)w[3 + ch] + (chunkIndex * x->nAmbiFrameSize),
                       x->nAmbiFrameSize * sizeof(t_sample));
            }
            // TODO: process
        }
    }

    return (w + 3 + x->nIn);
}

// ─────────────────────────────────────
void sldoa_tilde_dsp(t_sldoa_tilde *x, t_signal **sp) {
    // sldoa_getFrameSize has fixed frameSize, for sldoa is 64 for
    // decoder is 128. In the perform method sometimes I need to accumulate
    // samples sometimes I need to process 2 or more times to avoid change how
    // sldoa_ works. I think that in this way is more safe, once that these
    // functions are tested in the main repo. But maybe worse to implement the own
    // set of functions.

    x->nAmbiFrameSize = sldoa_getFrameSize();
    x->nPdFrameSize = sp[0]->s_n;
    x->nOutAccIndex = 0;
    x->nInAccIndex = 0;
    x->nIn = x->multichannel ? sp[0]->s_nchans : x->nIn;

    int sum = x->nIn;
    int sigvecsize = sum + 2;

    if (x->nPreviousIn != x->nIn) {
        sldoa_tilde_malloc(x);
        x->nPreviousIn = x->nIn;
    }

    if (sp[0]->s_nchans > 1 && !x->multichannel) {
        pd_error(x, "Multichannel mode is off, but input is multichannel, use '-m' flag");
    }

    // add perform method
    if (x->multichannel) {
        x->nIn = sp[0]->s_nchans;
        dsp_add(sldoa_tilde_performmultichannel, 3, x, sp[0]->s_n, sp[0]->s_vec);
    } else {
        for (int i = x->nIn; i < sum; i++) {
            signal_setmultiout(&sp[i], 1);
        }
        t_int *sigvec = getbytes(sigvecsize * sizeof(t_int));
        sigvec[0] = (t_int)x;
        sigvec[1] = (t_int)sp[0]->s_n;
        for (int i = 0; i < sum; i++) {
            sigvec[2 + i] = (t_int)sp[i]->s_vec;
        }
        dsp_addv(sldoa_tilde_perform, sigvecsize, sigvec);
        freebytes(sigvec, sigvecsize * sizeof(t_int));
    }
}

// ─────────────────────────────────────
void *sldoa_tilde_new(t_symbol *s, int argc, t_atom *argv) {
    if (argc < 1) {
        pd_error(NULL, "[saf.sldoa~] Wrong number of arguments, use [saf.sldoa~ "
                       "<num_sources>] or [saf.sldoa~ -m <ambisonic_order>] "
                       "for multichannel input");
        return NULL;
    }

    t_sldoa_tilde *x = (t_sldoa_tilde *)pd_new(sldoa_tilde_class);
    int order = 1;
    int num_sources = 4;
    if (argv[0].a_type == A_SYMBOL) {
        if (strcmp(atom_getsymbol(argv)->s_name, "-m") != 0) {
            pd_error(x, "[saf.sldoa~] Expected '-m' in second argument.");
            return NULL;
        }
        order = (argc >= 1) ? atom_getint(argv + 1) : 1;
        x->multichannel = 1;
    } else {
        num_sources = (argc >= 2) ? atom_getint(argv) : 1;
        x->multichannel = 0;
    }

    sldoa_create(&x->hAmbi);
    sldoa_init(x->hAmbi, sys_getsr());
    x->nOrder = order;
    x->nIn = num_sources;

    if (!x->multichannel) {
        for (int i = 1; i < x->nIn; i++) {
            inlet_new(&x->obj, &x->obj.ob_pd, &s_signal, &s_signal);
        }
    }

    return x;
}

// ─────────────────────────────────────
void sldoa_tilde_free(t_sldoa_tilde *x) {
    sldoa_destroy(&x->hAmbi);
    for (int i = 0; i < x->nIn; i++) {
        if (x->aIns) {
            freebytes(x->aIns[i], x->nAmbiFrameSize * sizeof(t_sample));
        }
        if (x->aInsTmp) {
            freebytes(x->aInsTmp[i], x->nAmbiFrameSize * sizeof(t_sample));
        }
    }

    if (x->aIns) {
        freebytes(x->aIns, x->nIn * sizeof(t_sample *));
    }
    if (x->aInsTmp) {
        freebytes(x->aInsTmp, x->nIn * sizeof(t_sample *));
    }
}

// ─────────────────────────────────────
void setup_saf0x2esldoa_tilde(void) {
    sldoa_tilde_class =
        class_new(gensym("saf.sldoa~"), (t_newmethod)sldoa_tilde_new, (t_method)sldoa_tilde_free,
                  sizeof(t_sldoa_tilde), CLASS_DEFAULT | CLASS_MULTICHANNEL, A_GIMME, 0);

    CLASS_MAINSIGNALIN(sldoa_tilde_class, t_sldoa_tilde, sample);
    class_addmethod(sldoa_tilde_class, (t_method)sldoa_tilde_dsp, gensym("dsp"), A_CANT, 0);

    // class_addmethod(sldoa_tilde_class, (t_method)sldoa_tilde_set, gensym("set"), A_GIMME, 0);
    class_addmethod(sldoa_tilde_class, (t_method)sldoa_tilde_set, gensym("solo"), A_GIMME, 0);
    class_addmethod(sldoa_tilde_class, (t_method)sldoa_tilde_set, gensym("normtype"), A_GIMME, 0);
    class_addmethod(sldoa_tilde_class, (t_method)sldoa_tilde_set, gensym("sourcegain"), A_GIMME, 0);
}
