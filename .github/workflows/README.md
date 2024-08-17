# CI/CD Using Github Actions

`terraform.yml` files automated the terraform code formatting, initialization, validation, and deployment. The job will be executed when there are changes made in `./terraform/**` directories, except in the `README.md` file inside the `./terraform` directory, based on this following statement:
```yaml
on:
  push:
    branches:
      - main
    paths:
      - terraform/**
      - '!terraform/README.md'
  pull_request:
    branches:
      - main
    paths:
      - terraform/**
      - '!terraform/README.md'
```

Specifically for the `terraform plan` and `terraform apply` stages, these stage will only be executed if an event specified in the `if` statement:

```yaml
    - name: Terraform plan
      id: plan
      if: github.event_name == 'pull_request'
      run: terraform plan -no-color -input=false
      continue-on-error: true
```
```yaml
    - name: Terraform Apply  # The deployment to AWS
      id: apply
      if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      run: terraform apply -auto-approve
```

Success execution of this Github Actions file can be seen in the `test: test workflow` commit.
