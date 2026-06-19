/**
 * Centralized pip command flag generation for Odysseus frontend.
 * Single source of truth for `--user --break-system-packages` pip flags.
 */

/**
 * Get pip flags based on environment type.
 * 
 * The --user and --break-system-packages flags should only be added when
 * NOT inside a venv/conda environment. Inside venv/conda, these flags are
 * invalid and pip will refuse them. For bare system Python environments
 * (especially PEP-668-locked systems like Arch Linux or newer Debian),
 * these flags are needed to allow user-level package installs.
 * 
 * @param {string} envType - The environment type: 'venv', 'conda', 'bare', or undefined
 * @returns {string} - Returns ' --user --break-system-packages' if NOT in venv/conda,
 *                     otherwise returns empty string ''
 * 
 * @example
 * getPipFlags('venv')     // Returns ''
 * getPipFlags('conda')    // Returns ''
 * getPipFlags('bare')     // Returns ' --user --break-system-packages'
 * getPipFlags(undefined)  // Returns ' --user --break-system-packages'
 */
function getPipFlags(envType) {
  // If in venv or conda, don't add flags (they're invalid in these environments)
  if (envType === 'venv' || envType === 'conda') {
    return '';
  }
  // For bare/system Python or undefined, add the flags for PEP-668 compliance
  return ' --user --break-system-packages';
}

/**
 * Build a complete pip install command with environment-aware flags.
 * 
 * @param {string} pythonExe - The Python executable to use (e.g., 'python3', '/path/to/venv/bin/python3')
 * @param {string} packageName - The package name to install
 * @param {string} envType - The environment type (optional, used to determine flags)
 * @param {boolean} upgrade - Whether to add the -U flag for upgrade (default: false)
 * @returns {string} - The complete pip install command
 * 
 * @example
 * buildPipInstallCommand('python3', 'numpy', 'bare')
 * // Returns: 'python3 -m pip install --user --break-system-packages "numpy"'
 * 
 * buildPipInstallCommand('python3', 'numpy', 'venv')
 * // Returns: 'python3 -m pip install "numpy"'
 * 
 * buildPipInstallCommand('python3', 'numpy', 'venv', true)
 * // Returns: 'python3 -m pip install -U "numpy"'
 */
function buildPipInstallCommand(pythonExe, packageName, envType, upgrade = false) {
  const flags = getPipFlags(envType);
  const upgradeFlag = upgrade ? ' -U' : '';
  return `${pythonExe} -m pip install${upgradeFlag}${flags} "${packageName}"`;
}

/**
 * Export functions for use in other modules
 */
export { getPipFlags, buildPipInstallCommand };
