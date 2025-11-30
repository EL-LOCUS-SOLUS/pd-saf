#include <string.h>

#include <m_pd.h>
#include <g_canvas.h>

#include "utilities.h"
#include <panner.h>

static t_class *panner_tilde_class;

// ─────────────────────────────────────
typedef struct _panner_tilde {
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
    int nOut;
    int nPreviousIn;
    int nPreviousOut;

    int multichannel;
} t_panner_tilde;

// ─────────────────────────────────────
static void panner_tilde_malloc(t_panner_tilde *x) {
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
    if (x->aOuts) {
        for (int i = 0; i < x->nOut; i++) {
            if (x->aOuts[i]) {
                freebytes(x->aOuts[i], x->nAmbiFrameSize * sizeof(t_sample));
            }
            if (x->aOutsTmp[i]) {
                freebytes(x->aOutsTmp[i], x->nAmbiFrameSize * sizeof(t_sample));
            }
        }
        freebytes(x->aOuts, x->nOut * sizeof(t_sample *));
    }

    // memory allocation
    x->aIns = (t_sample **)getbytes(x->nIn * sizeof(t_sample *));
    x->aInsTmp = (t_sample **)getbytes(x->nIn * sizeof(t_sample *));
    x->aOuts = (t_sample **)getbytes(x->nOut * sizeof(t_sample *));
    x->aOutsTmp = (t_sample **)getbytes(x->nOut * sizeof(t_sample *));

    for (int i = 0; i < x->nIn; i++) {
        x->aIns[i] = (t_sample *)getbytes(x->nAmbiFrameSize * sizeof(t_sample));
        x->aInsTmp[i] = (t_sample *)getbytes(x->nAmbiFrameSize * sizeof(t_sample));
    }
    for (int i = 0; i < x->nOut; i++) {
        x->aOuts[i] = (t_sample *)getbytes(x->nAmbiFrameSize * sizeof(t_sample));
        x->aOutsTmp[i] = (t_sample *)getbytes(x->nAmbiFrameSize * sizeof(t_sample));
    }
    x->nPreviousIn = x->nIn;
    x->nPreviousOut = x->nOut;
}

// ─────────────────────────────────────
static void panner_tilde_set(t_panner_tilde *x, t_symbol *s, int argc, t_atom *argv) {
    const char *method = s->s_name;
    if (strcmp(method, "source") == 0) {
        int index = atom_getint(argv) - 1;
        float azi = atom_getfloat(argv + 1);
        float ele = atom_getfloat(argv + 2);
        panner_setSourceAzi_deg(x->hAmbi, index, azi);
        panner_setSourceElev_deg(x->hAmbi, index, ele);
    } else if (strcmp(method, "speaker") == 0) {
        int index = atom_getint(argv);
        float azi = atom_getfloat(argv + 1);
        float ele = atom_getfloat(argv + 2);
        panner_setLoudspeakerAzi_deg(x->hAmbi, index, azi);
        panner_setLoudspeakerElev_deg(x->hAmbi, index, ele);
    } else if (strcmp(method, "dtt") == 0) {
        float dtt = atom_getfloat(argv);
        if (dtt > 1 || dtt < 0) {
            pd_error(x, "[saf.panner~] dtt must be between 0 and 1");
            return;
        }
        panner_setDTT(x->hAmbi, dtt);
        x->hAmbiInit = 0;
        canvas_update_dsp();
    } else if (strcmp(method, "spread") == 0) {
        float spread = atom_getfloat(argv);
        panner_setSpread(x->hAmbi, spread);
        x->hAmbiInit = 0;
        canvas_update_dsp();
    }
}

// ─────────────────────────────────────
t_int *panner_tilde_performmultichannel(t_int *w) {
    t_panner_tilde *x = (t_panner_tilde *)(w[1]);
    int n = (int)(w[2]);
    t_sample *ins = (t_sample *)(w[3]);
    t_sample *outs = (t_sample *)(w[4]);

    if (n < x->nAmbiFrameSize) {
        for (int ch = 0; ch < x->nIn; ch++) {
            memcpy(x->aIns[ch] + x->nInAccIndex, ins + (n * ch), n * sizeof(t_sample));
        }
        x->nInAccIndex += n;

        // Process only if a full frame is ready
        if (x->nInAccIndex == x->nAmbiFrameSize) {
            panner_process(x->hAmbi, (const float *const *)x->aIns, (float *const *)x->aOuts,
                           x->nIn, x->nOut, x->nAmbiFrameSize);
            x->nInAccIndex = 0;
            x->nOutAccIndex = 0; // Reset for the next frame
        }

        if (x->nOutAccIndex + n <= x->nAmbiFrameSize) {
            // Copy valid processed data
            for (int ch = 0; ch < x->nOut; ch++) {
                memcpy(outs + (n * ch), x->aOuts[ch] + x->nOutAccIndex, n * sizeof(t_sample));
            }
            x->nOutAccIndex += n;
        } else {
            for (int ch = 0; ch < x->nOut; ch++) {
                memset(outs + (n * ch), 0, n * sizeof(t_sample));
            }
        }
    } else {
        int chunks = n / x->nAmbiFrameSize;
        for (int chunkIndex = 0; chunkIndex < chunks; chunkIndex++) {
            // Copia os dados de entrada para cada canal
            for (int ch = 0; ch < x->nIn; ch++) {
                memcpy(x->aInsTmp[ch], (t_sample *)w[3] + ch * n + chunkIndex * x->nAmbiFrameSize,
                       x->nAmbiFrameSize * sizeof(t_sample));
            }
            // Processa o bloco atual
            panner_process(x->hAmbi, (const float *const *)x->aInsTmp, (float *const *)x->aOutsTmp,
                           x->nIn, x->nOut, x->nAmbiFrameSize);

            t_sample *out = (t_sample *)(w[4]);
            // Copia o resultado para os canais de saída com o offset correto
            for (int ch = 0; ch < x->nOut; ch++) {
                memcpy(out + ch * n + chunkIndex * x->nAmbiFrameSize, x->aOutsTmp[ch],
                       x->nAmbiFrameSize * sizeof(t_sample));
            }
        }
    }

    return (w + 5);
}

// ─────────────────────────────────────
t_int *panner_tilde_perform(t_int *w) {
    t_panner_tilde *x = (t_panner_tilde *)(w[1]);
    int n = (int)(w[2]);

    if (n < x->nAmbiFrameSize) {
        for (int ch = 0; ch < x->nIn; ch++) {
            memcpy(x->aIns[ch] + x->nInAccIndex, (t_sample *)w[3 + ch], n * sizeof(t_sample));
        }
        x->nInAccIndex += n;
        if (x->nInAccIndex == x->nAmbiFrameSize) {
            panner_process(x->hAmbi, (const float *const *)x->aIns, (float *const *)x->aOuts,
                           x->nIn, x->nOut, x->nAmbiFrameSize);
            x->nInAccIndex = 0;
            x->nOutAccIndex = 0;
        }
        for (int ch = 0; ch < x->nOut; ch++) {
            t_sample *out = (t_sample *)(w[3 + x->nIn + ch]);
            memcpy(out, x->aOuts[ch] + x->nOutAccIndex, n * sizeof(t_sample));
        }
        x->nOutAccIndex += n;
    } else {
        int chunks = n / x->nAmbiFrameSize;
        for (int chunkIndex = 0; chunkIndex < chunks; chunkIndex++) {
            for (int ch = 0; ch < x->nIn; ch++) {
                memcpy(x->aInsTmp[ch], (t_sample *)w[3 + ch] + (chunkIndex * x->nAmbiFrameSize),
                       x->nAmbiFrameSize * sizeof(t_sample));
            }
            panner_process(x->hAmbi, (const float *const *)x->aInsTmp, (float *const *)x->aOutsTmp,
                           x->nIn, x->nOut, x->nAmbiFrameSize);
            for (int ch = 0; ch < x->nOut; ch++) {
                t_sample *out = (t_sample *)(w[3 + x->nIn + ch]);
                memcpy(out + (chunkIndex * x->nAmbiFrameSize), x->aOutsTmp[ch],
                       x->nAmbiFrameSize * sizeof(t_sample));
            }
        }
    }

    return (w + 3 + x->nIn + x->nOut);
}

// ─────────────────────────────────────
void panner_tilde_dsp(t_panner_tilde *x, t_signal **sp) {
    // panner_getFrameSize has fixed frameSize, for panner is 64 for
    // decoder is 128. In the perform method sometimes I need to accumulate
    // samples sometimes I need to process 2 or more times to avoid change how
    // panner_ works. I think that in this way is more safe, once that these
    // functions are tested in the main repo. But maybe worse to implement the own
    // set of functions.

    x->nAmbiFrameSize = panner_getFrameSize();
    x->nPdFrameSize = sp[0]->s_n;
    x->nOutAccIndex = 0;
    x->nInAccIndex = 0;

    x->nIn = x->multichannel ? sp[0]->s_nchans : x->nIn;
    int sum = x->nIn + x->nOut;
    int sigvecsize = sum + 2;

    panner_setNumSources(x->hAmbi, x->nIn);
    panner_setNumLoudspeakers(x->hAmbi, x->nOut);
    if (!x->hAmbiInit) {
        panner_initCodec(x->hAmbi);
        x->hAmbiInit = 1;
    }

    if (x->nPreviousIn != x->nIn || x->nPreviousOut != x->nOut) {
        panner_setNumSources(x->hAmbi, x->nIn);
        panner_tilde_malloc(x);
        for (int i = 0; i < x->nIn; i++) {
            float azi = 360.0f / x->nOut * i;
            panner_setSourceAzi_deg(x->hAmbi, i, azi);
            panner_setSourceElev_deg(x->hAmbi, i, 0);
        }
        x->nPreviousIn = x->nIn;
        x->nPreviousIn = x->nOut;
    }

    if (sp[0]->s_nchans > 1 && !x->multichannel) {
        pd_error(x, "Multichannel mode is off, but input is multichannel, use '-m' flag");
    }

    // add perform method
    if (x->multichannel) {
        x->nIn = sp[0]->s_nchans;
        signal_setmultiout(&sp[1], x->nOut);
        dsp_add(panner_tilde_performmultichannel, 4, x, sp[0]->s_n, sp[0]->s_vec, sp[1]->s_vec);
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
        dsp_addv(panner_tilde_perform, sigvecsize, sigvec);
        freebytes(sigvec, sigvecsize * sizeof(t_int));
    }
}

// ─────────────────────────────────────
void *panner_tilde_new(t_symbol *s, int argc, t_atom *argv) {
    if (argc < 2) {
        pd_error(NULL, "[saf.panner~] Wrong number of arguments, use [saf.panner~ "
                       "<num_sources> <ambisonic_order>] or [saf.panner~ -m <ambisonic_order>] "
                       "for multichannel input");
        return NULL;
    }

    t_panner_tilde *x = (t_panner_tilde *)pd_new(panner_tilde_class);
    int num_sources = 4;
    int num_speakers = 1;
    if (argv[0].a_type == A_SYMBOL) {
        if (strcmp(atom_getsymbol(argv)->s_name, "-m") != 0) {
            pd_error(x, "[saf.panner~] Expected '-m' in second argument.");
            return NULL;
        }
        num_speakers = (argc >= 1) ? atom_getint(argv + 1) : 1;
        x->multichannel = 1;
    } else {
        num_sources = (argc >= 2) ? atom_getint(argv) : 1;
        num_speakers = (argc >= 1) ? atom_getint(argv + 1) : 1;
        x->multichannel = 0;
    }

    panner_create(&x->hAmbi);
    panner_init(x->hAmbi, sys_getsr());
    x->nOrder = 1;
    x->nIn = num_sources;
    x->nOut = num_speakers;

    if (x->multichannel) {
        outlet_new(&x->obj, &s_signal);
    } else {
        for (int i = 1; i < x->nIn; i++) {
            inlet_new(&x->obj, &x->obj.ob_pd, &s_signal, &s_signal);
        }
        for (int i = 0; i < x->nOut; i++) {
            outlet_new(&x->obj, &s_signal);
        }
    }

    return x;
}

// ─────────────────────────────────────
void panner_tilde_free(t_panner_tilde *x) {
    panner_destroy(&x->hAmbi);
    for (int i = 0; i < x->nIn; i++) {
        if (x->aIns) {
            freebytes(x->aIns[i], x->nAmbiFrameSize * sizeof(t_sample));
        }
        if (x->aInsTmp) {
            freebytes(x->aInsTmp[i], x->nAmbiFrameSize * sizeof(t_sample));
        }
    }
    for (int i = 0; i < x->nOut; i++) {
        if (x->aOuts) {
            freebytes(x->aOuts[i], x->nAmbiFrameSize * sizeof(t_sample));
        }
        if (x->aOutsTmp) {
            freebytes(x->aOutsTmp[i], x->nAmbiFrameSize * sizeof(t_sample));
        }
    }

    if (x->aIns) {
        freebytes(x->aIns, x->nIn * sizeof(t_sample *));
    }
    if (x->aInsTmp) {
        freebytes(x->aInsTmp, x->nIn * sizeof(t_sample *));
    }
    if (x->aOuts) {
        freebytes(x->aOuts, x->nOut * sizeof(t_sample *));
    }
    if (x->aOutsTmp) {
        freebytes(x->aOutsTmp, x->nOut * sizeof(t_sample *));
    }
}

// ─────────────────────────────────────
// clang-format off
void setup_saf0x2epanner_tilde(void) {
    panner_tilde_class =
        class_new(gensym("saf.panner~"), (t_newmethod)panner_tilde_new, (t_method)panner_tilde_free,
                  sizeof(t_panner_tilde), CLASS_DEFAULT | CLASS_MULTICHANNEL, A_GIMME, 0);

    CLASS_MAINSIGNALIN(panner_tilde_class, t_panner_tilde, sample);
    class_addmethod(panner_tilde_class, (t_method)panner_tilde_dsp, gensym("dsp"), A_CANT, 0);

    class_addmethod(panner_tilde_class, (t_method)panner_tilde_set, gensym("source"), A_GIMME, 0);
    class_addmethod(panner_tilde_class, (t_method)panner_tilde_set, gensym("speaker"), A_GIMME, 0);
    class_addmethod(panner_tilde_class, (t_method)panner_tilde_set, gensym("dtt"), A_GIMME, 0);
    class_addmethod(panner_tilde_class, (t_method)panner_tilde_set, gensym("spread"), A_GIMME, 0);
}
