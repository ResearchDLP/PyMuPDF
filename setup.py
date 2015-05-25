from distutils.core import setup, Extension
import sys

# check the platform
if sys.platform.startswith('linux'):
    module = Extension('fitz._fitz', # name of the module
                       ['fitz/fitz.i'], # SWIG source file
                       include_dirs=['/usr/include/mupdf'], # we need the path of the MuPDF's headers
                       libraries=['mupdf', 'mujs', 'crypto', 'jbig2dec', 'openjp2', 'jpeg', 'freetype'], # the libraries to link with
                      )
else:
#===============================================================================
# This will build / setup python-fitz under Windows
# There is a wiki page with detailed instructions on how to set up
# python-fitz in Windows 7.
#===============================================================================
    module = Extension('fitz._fitz',
                       include_dirs=['./fitz', './mupdf12/fitz'],    # mupdf source directory is also needed
                       libraries=['libmupdf-nov8',                   # only these are needed in Windows
                                  'libmupdf',                        # put them in the dir of setupwin.py or
                                  'libthirdparty'],                  # specify a lib directory here
                       extra_link_args=['/NODEFAULTLIB:LIBCMT'],     # not doing this results in unresolved symbols
                       sources=['./fitz/fitz_wrap.c'])

setup(name = 'fitz',
      version = '1.7.0',
      description = 'Python bindings for the MuPDF rendering library',
      classifiers = ['Development Status :: 4 - Beta',
                     'Environment :: Console',
                     'Intended Audience :: Developers',
                     'License :: OSI Approved :: GNU General Public License v3 or later (GPLv3+)',
                     'Operating System :: WINDOWS',
                     'Programming Language :: C',
                     'Topic :: Utilities'],
      url = 'https://github.com/rk700/python-fitz',
      author = 'Ruikai Liu',
      author_email = 'lrk700@gmail.com',
      license = 'GPLv3+',
      ext_modules = [module],
      py_modules = ['fitz.fitz'])