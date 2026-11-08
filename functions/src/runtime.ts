/**
 * The service account the functions run as.
 *
 * 1st-gen functions default to the App Engine account
 * (<project>@appspot.gserviceaccount.com), which projects created since 2024
 * no longer get unless an App Engine app is created. Set
 * FUNCTIONS_SERVICE_ACCOUNT (in functions/.env.<projectId>) to run as another
 * account instead, such as the Compute Engine default
 * (<project-number>-compute@developer.gserviceaccount.com). Unset, the
 * default applies.
 */
export const runAs: {serviceAccount?: string} =
  process.env.FUNCTIONS_SERVICE_ACCOUNT ?
    {serviceAccount: process.env.FUNCTIONS_SERVICE_ACCOUNT} :
    {};
