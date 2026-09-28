begin;
select foundation.get_readiness_dependency_proposal_status_v1(gen_random_uuid());
rollback;
