//! The management API's OpenAPI document at `/api/docs-json` and Swagger UI at `/api/docs`.

use axum::Router;
use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};
use utoipa::{Modify, OpenApi};
use utoipa_swagger_ui::SwaggerUi;

use super::AppState;
use super::installations;

struct BearerAuth;

impl Modify for BearerAuth {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        let components = openapi.components.get_or_insert_with(Default::default);
        components.add_security_scheme(
            "bearer",
            SecurityScheme::Http(HttpBuilder::new().scheme(HttpAuthScheme::Bearer).build()),
        );
    }
}

#[derive(OpenApi)]
#[openapi(
    info(title = "BetterTG Backend", version = "1"),
    paths(
        installations::create,
        installations::update_apns_token,
        installations::rotate_subscription,
        installations::delete_subscription,
        installations::delete_installation,
    ),
    modifiers(&BearerAuth),
    tags((name = "Installations"))
)]
struct ApiDoc;

pub fn router() -> Router<AppState> {
    Router::from(SwaggerUi::new("/api/docs").url("/api/docs-json", ApiDoc::openapi()))
}
