%{
//----------------------------------------------------------------------------
// convert (char *) to ASCII-only (char*) (which must be freed!)
//----------------------------------------------------------------------------
char *JM_ASCIIFromChar(char *in)
{
    if (!in) return NULL;
    size_t i, j = strlen(in);
    unsigned char *out = (unsigned char *) malloc(j+1);
    if (!out) return NULL;
    memcpy(out, in, j+1);
    for (i = 0; i < j; i++)
    {
        if (out[i] > 126)
        {
            out[i] = 63;
            continue;
        }
        if (out[i] < 32)
            out[i] = 32;
    }
    return (char *) out;
}

//----------------------------------------------------------------------------
// create an ASCII-only Python string of a (char*)
//----------------------------------------------------------------------------
PyObject *JM_UnicodeFromASCII(const char *in)
{
    char *c = JM_ASCIIFromChar((char *) in);
    PyObject *p = Py_BuildValue("s", c);
    free(c);
    return p;
}

//-----------------------------------------------------------------------------
// Store info of a font in Python list
//-----------------------------------------------------------------------------
void JM_gatherfonts(fz_context *ctx, pdf_document *pdf, pdf_obj *dict,
                    PyObject *fontlist)
{
    int i, n;
    n = pdf_dict_len(ctx, dict);
    for (i = 0; i < n; i++)
    {
        pdf_obj *fontdict = NULL;
        pdf_obj *subtype = NULL;
        pdf_obj *basefont = NULL;
        pdf_obj *name = NULL;
        pdf_obj *refname = NULL;
        pdf_obj *encoding = NULL;

        fontdict = pdf_dict_get_val(ctx, dict, i);
        if (!pdf_is_dict(ctx, fontdict))
        {
            PySys_WriteStdout("warning: not a font dict (%d 0 R)",
                              pdf_to_num(ctx, fontdict));
            continue;
        }
        refname = pdf_dict_get_key(ctx, dict, i);
        subtype = pdf_dict_get(ctx, fontdict, PDF_NAME_Subtype);
        basefont = pdf_dict_get(ctx, fontdict, PDF_NAME_BaseFont);
        if (!basefont || pdf_is_null(ctx, basefont))
            name = pdf_dict_get(ctx, fontdict, PDF_NAME_Name);
        else
            name = basefont;
        encoding = pdf_dict_get(ctx, fontdict, PDF_NAME_Encoding);
        if (pdf_is_dict(ctx, encoding))
            encoding = pdf_dict_get(ctx, encoding, PDF_NAME_BaseEncoding);
        int xref = pdf_to_num(ctx, fontdict);
        char *ext = "n/a";
        if (xref) ext = fontextension(ctx, pdf, xref);
        PyObject *entry = PyList_New(0);
        PyList_Append(entry, Py_BuildValue("i", xref));
        PyList_Append(entry, Py_BuildValue("s", ext));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, subtype)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, name)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, refname)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, encoding)));
        PyList_Append(fontlist, entry);
        Py_DECREF(entry);
    }
}

//-----------------------------------------------------------------------------
// Store info of an image in Python list
//-----------------------------------------------------------------------------
void JM_gatherimages(fz_context *ctx, pdf_document *doc, pdf_obj *dict,
                     PyObject *imagelist)
{
    int i, n;
    n = pdf_dict_len(ctx, dict);
    for (i = 0; i < n; i++)
    {
        pdf_obj *imagedict, *smask;
        pdf_obj *refname = NULL;
        pdf_obj *type;
        pdf_obj *width;
        pdf_obj *height;
        pdf_obj *bpc = NULL;
        pdf_obj *filter = NULL;
        pdf_obj *cs = NULL;
        pdf_obj *altcs;

        imagedict = pdf_dict_get_val(ctx, dict, i);
        if (!pdf_is_dict(ctx, imagedict))
        {
            PySys_WriteStdout("warning: not an image dict (%d 0 R)",
                              pdf_to_num(ctx, imagedict));
            continue;
        }
        refname = pdf_dict_get_key(ctx, dict, i);

        type = pdf_dict_get(ctx, imagedict, PDF_NAME_Subtype);
        if (!pdf_name_eq(ctx, type, PDF_NAME_Image))
            continue;
        
        int xref = pdf_to_num(ctx, imagedict);
        int gen = 0;
        smask = pdf_dict_get(ctx, imagedict, PDF_NAME_SMask);
        if (smask)
            gen = pdf_to_num(ctx, smask);
        filter = pdf_dict_get(ctx, imagedict, PDF_NAME_Filter);

        altcs = NULL;
        cs = pdf_dict_get(ctx, imagedict, PDF_NAME_ColorSpace);
        if (pdf_is_array(ctx, cs))
        {
            pdf_obj *cses = cs;
            cs = pdf_array_get(ctx, cses, 0);
            if (pdf_name_eq(ctx, cs, PDF_NAME_DeviceN) ||
                pdf_name_eq(ctx, cs, PDF_NAME_Separation))
            {
                altcs = pdf_array_get(ctx, cses, 2);
                if (pdf_is_array(ctx, altcs))
                    altcs = pdf_array_get(ctx, altcs, 0);
            }
        }

        width = pdf_dict_get(ctx, imagedict, PDF_NAME_Width);
        height = pdf_dict_get(ctx, imagedict, PDF_NAME_Height);
        bpc = pdf_dict_get(ctx, imagedict, PDF_NAME_BitsPerComponent);

        PyObject *entry = PyList_New(0);
        PyList_Append(entry, Py_BuildValue("i", xref));
        PyList_Append(entry, Py_BuildValue("i", gen));
        PyList_Append(entry, Py_BuildValue("i", pdf_to_int(ctx, width)));
        PyList_Append(entry, Py_BuildValue("i", pdf_to_int(ctx, height)));
        PyList_Append(entry, Py_BuildValue("i", pdf_to_int(ctx, bpc)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, cs)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, altcs)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, refname)));
        PyList_Append(entry, JM_UnicodeFromASCII(pdf_to_name(ctx, filter)));
        PyList_Append(imagelist, entry);
        Py_DECREF(entry);
    }
}

//-----------------------------------------------------------------------------
// Step through /Resources, looking up image or font information
//-----------------------------------------------------------------------------
void JM_ScanResources(fz_context *ctx, pdf_document *pdf, pdf_obj *rsrc,
                 PyObject *liste, int what)
{
    pdf_obj *font, *xobj, *subrsrc;
    int i, n;
    if (pdf_mark_obj(ctx, rsrc)) return;    // stop on cylic dependencies
    fz_try(ctx)
    {
        if (what == 1)            // looking up fonts
        {
            font = pdf_dict_get(ctx, rsrc, PDF_NAME_Font);
            JM_gatherfonts(ctx, pdf, font, liste);
            n = pdf_dict_len(ctx, font);
            for (i = 0; i < n; i++)
            {
                pdf_obj *obj = pdf_dict_get_val(ctx, font, i);
                subrsrc = pdf_dict_get(ctx, obj, PDF_NAME_Resources);
                if (subrsrc)
                    JM_ScanResources(ctx, pdf, subrsrc, liste, what);
            }
        }

        xobj = pdf_dict_get(ctx, rsrc, PDF_NAME_XObject);

        if (what == 2)            // looking up images
        {
            JM_gatherimages(ctx, pdf, xobj, liste);
        }

        n = pdf_dict_len(ctx, xobj);
        for (i = 0; i < n; i++)
        {
            pdf_obj *obj = pdf_dict_get_val(ctx, xobj, i);
            subrsrc = pdf_dict_get(ctx, obj, PDF_NAME_Resources);
            if (subrsrc)
                JM_ScanResources(ctx, pdf, subrsrc, liste, what);
        }
    }
    fz_always(ctx) pdf_unmark_obj(ctx, rsrc);
    fz_catch(ctx)  fz_rethrow(ctx);
}

%}