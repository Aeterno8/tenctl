@ECHO OFF

pushd %~dp0

REM Command file for Sphinx documentation

if "%SPHINXBUILD%" == "" (
	set SPHINXBUILD=sphinx-build
)
set SOURCEDIR=source
set BUILDDIR=build
set SCRIPTSDIR=scripts

if "%1" == "" goto help
if "%1" == "extract-docs" goto extract-docs
if "%1" == "extract-cli" goto extract-cli
if "%1" == "extract-modules" goto extract-modules
if "%1" == "clean-extract" goto clean-extract

%SPHINXBUILD% >NUL 2>NUL
if errorlevel 9009 (
	echo.
	echo.The 'sphinx-build' command was not found. Make sure you have Sphinx
	echo.installed, then set the SPHINXBUILD environment variable to point
	echo.to the full path of the 'sphinx-build' executable. Alternatively you
	echo.may add the Sphinx directory to PATH.
	echo.
	echo.If you don't have Sphinx installed, grab it from
	echo.https://www.sphinx-doc.org/
	exit /b 1
)

%SPHINXBUILD% -M %1 %SOURCEDIR% %BUILDDIR% %SPHINXOPTS% %O%
goto end

:help
%SPHINXBUILD% -M help %SOURCEDIR% %BUILDDIR% %SPHINXOPTS% %O%
goto end

:extract-docs
echo.Extracting CLI command documentation...
python %SCRIPTSDIR%\extract_cli_docs.py
echo.Extracting module documentation...
python %SCRIPTSDIR%\extract_module_docs.py
goto end

:extract-cli
echo.Extracting CLI command documentation...
python %SCRIPTSDIR%\extract_cli_docs.py
goto end

:extract-modules
echo.Extracting module documentation...
python %SCRIPTSDIR%\extract_module_docs.py
goto end

:clean-extract
echo.Cleaning extracted documentation...
del /Q %SOURCEDIR%\reference\commands\*.rst 2>NUL
del /Q %SOURCEDIR%\reference\modules\*.rst 2>NUL
echo.Extracted documentation cleaned.
goto end

:end
popd
