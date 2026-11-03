import pytest

from services.errors import STATUS_BY_CODE, ApiError


@pytest.mark.parametrize("code,status", sorted(STATUS_BY_CODE.items()))
def test_each_code_has_its_status(code, status):
    assert ApiError(code, "x").status == status


def test_the_code_list_matches_api_md():
    assert set(STATUS_BY_CODE) == {"bad_request", "unauthorized", "forbidden", "not_found", "conflict", "internal"}


def test_unknown_code_is_refused():
    with pytest.raises(ValueError):
        ApiError("oops", "x")
